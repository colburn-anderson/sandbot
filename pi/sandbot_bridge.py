#!/usr/bin/env python3
"""
sandbot_bridge.py — Flask HTTP bridge between the SandBot iOS app and the
Freenove Robot Arm server (TCP socket on port 5000).

Architecture:
  [iOS App] --HTTP--> [This Bridge :8080] --TCP--> [Freenove Server :5000]

The bridge:
  1. Accepts image uploads (or rendered text images) via HTTP
  2. Runs the exact same OpenCV pipeline as the Freenove GUI client
     (gray → threshold → gaussian blur → sharpen → contour → G-code)
  3. Sends the resulting G-code commands to the Freenove server via TCP
     using its flow-controlled protocol
  4. Returns job status to the iOS app via HTTP

Run this ON THE PI alongside main.py:
  sudo python sandbot_bridge.py
"""

import os
import io
import time
import json
import uuid
import socket
import threading
import traceback
from datetime import datetime
from flask import Flask, request, jsonify, send_file
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from boundary import Boundary, reachable

app = Flask(__name__)

# ── FREENOVE SERVER CONNECTION ───────────────────────────────────────
FREENOVE_HOST = "127.0.0.1"
FREENOVE_PORT = 5000

# ── SAND PIT BOUNDARY ───────────────────────────────────────────────
# The drawing canvas covers the pit's bounding box; anything outside the
# kidney outline is clipped. Pixel top = far side of the pit (max Y).
boundary = Boundary()
MM_PER_PX = 200 / 561      # same scale as the old 561px → 200mm GUI canvas

# ── DEFAULT IMAGE PROCESSING PARAMS ─────────────────────────────────
DEFAULT_THRESHOLD = 151
DEFAULT_GAUSS = 3
DEFAULT_SHARPEN = 7
DEFAULT_PEN_UP_HEIGHT = 15

# ── HOME / DRAWING POSITION ─────────────────────────────────────────
HOME_POSITION = [0.0, 200.0, 58.5]  # X, Y, Z — matches GUI defaults
FOLD_POSITION = [0.0, 50.0, 130.0]  # folded rest position

# ── CAMERA VIEW (REST) POSITION ─────────────────────────────────────
# Where the arm parks after a drawing: high enough for the arm-mounted
# camera to see the whole pit. Set from the app (calibration screen) and
# saved to robot_config.json.
ROBOT_CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "robot_config.json")
DEFAULT_VIEW_POSITION = [-16.0, 159.0, 270.5]
CAMERA_SNAPSHOT_URL = "http://127.0.0.1:8000/snapshot.jpg"
PHOTO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "photos")


def load_robot_config():
    try:
        with open(ROBOT_CONFIG_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_robot_config(cfg):
    with open(ROBOT_CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


def view_position():
    return load_robot_config().get("view_position", DEFAULT_VIEW_POSITION)

# ── IMAGE CANVAS SIZE (derived from the pit's bounding box) ─────────
def canvas_size():
    min_x, min_y, max_x, max_y = boundary.bbox()
    return (int(round((max_x - min_x) / MM_PER_PX)),
            int(round((max_y - min_y) / MM_PER_PX)))


def px_to_mm(px, py, size):
    """Canvas pixel → arm (x, y) in mm."""
    min_x, min_y, max_x, max_y = boundary.bbox()
    w, h = size
    return (round(min_x + (max_x - min_x) * px / w, 1),
            round(max_y - (max_y - min_y) * py / h, 1))


def mm_to_px(x, y, size):
    min_x, min_y, max_x, max_y = boundary.bbox()
    w, h = size
    return ((x - min_x) / (max_x - min_x) * w,
            (max_y - y) / (max_y - min_y) * h)

# ── JOB TRACKING ────────────────────────────────────────────────────
jobs = {}  # job_id -> {status, created_at, label, source, ...}
jobs_lock = threading.Lock()


# ════════════════════════════════════════════════════════════════════
# TCP CLIENT FOR FREENOVE SERVER
# ════════════════════════════════════════════════════════════════════

class FreenoveClient:
    """Manages TCP connection to the Freenove arm server."""

    def __init__(self):
        self.sock = None
        self.connected = False
        self.recv_buffer = ""
        self.arm_command_count = 0
        self.send_g_code_state = False
        self.lock = threading.Lock()
        self.pos = None          # last commanded [x, y, z]; None = unknown
        self.violation = None    # reason the last move was blocked
        self.abort = False       # set by /stop to cut a running batch short

    def connect(self):
        """Connect to the Freenove server."""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(10)
            self.sock.connect((FREENOVE_HOST, FREENOVE_PORT))
            self.connected = True
            # Start receive thread
            recv_thread = threading.Thread(target=self._receive_loop, daemon=True)
            recv_thread.start()
            print(f"[Bridge] Connected to Freenove server at {FREENOVE_HOST}:{FREENOVE_PORT}")
            return True
        except Exception as e:
            print(f"[Bridge] Failed to connect to Freenove server: {e}")
            self.connected = False
            return False

    def disconnect(self):
        """Disconnect from the Freenove server."""
        self.connected = False
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
            self.sock = None

    @staticmethod
    def _parse_move(cmd, pos):
        """Return the [x, y, z] target of a G0/G1 command, or None if not a move."""
        parts = cmd.split()
        if not parts or parts[0] not in ("G0", "G1"):
            return None
        target = list(pos) if pos else [None, None, None]
        for part in parts[1:]:
            axis = "XYZ".find(part[:1])
            if axis >= 0:
                target[axis] = float(part[1:])
        return target

    def send(self, cmd, trusted=False):
        """
        Send a command string to the Freenove server. G0/G1 moves are checked
        against the sand pit boundary unless `trusted` (fold / calibration).
        """
        if not self.connected or not self.sock:
            print(f"[Bridge] Not connected, cannot send: {cmd}")
            return False
        target = self._parse_move(cmd, self.pos)
        if target is not None:
            if None in target:
                reason = None if trusted else f"position unknown, refusing partial move '{cmd}'"
            else:
                reason = None if trusted else boundary.check_move(self.pos, target)
            if reason:
                self.violation = reason
                print(f"[Bridge] BOUNDARY BLOCKED: {reason}")
                return False
        elif cmd.startswith("S10"):
            self.pos = None  # homing moves the arm to its sensor pose
        try:
            with self.lock:
                self.sock.sendall((cmd + "\r\n").encode("utf-8"))
            if target is not None and None not in target:
                # Parked over the base (fold) → treat like after homing.
                self.pos = target if (target[0] ** 2 + target[1] ** 2) ** 0.5 >= 82 else None
            return True
        except Exception as e:
            print(f"[Bridge] Send error: {e}")
            self.connected = False
            return False

    def _receive_loop(self):
        """Background thread to receive and parse responses."""
        while self.connected:
            try:
                data = self.sock.recv(4096)
                if not data:
                    self.connected = False
                    break
                self.recv_buffer += data.decode("utf-8", errors="ignore")
                # Process complete messages (terminated by \r\n or similar)
                while "\r\n" in self.recv_buffer:
                    msg, self.recv_buffer = self.recv_buffer.split("\r\n", 1)
                    self._handle_message(msg.strip())
            except socket.timeout:
                continue
            except Exception as e:
                if self.connected:
                    print(f"[Bridge] Receive error: {e}")
                break
        self.connected = False

    def _handle_message(self, msg):
        """Parse incoming messages from the Freenove server."""
        if not msg:
            return
        print(f"[Bridge] RECV: {msg}")
        try:
            parts = msg.split()
            if len(parts) >= 2 and parts[0].startswith("S"):
                if "K" in parts[1]:
                    count_str = parts[1][1:]
                    try:
                        self.arm_command_count = int(count_str)
                        self.send_g_code_state = True
                        print(f"[Bridge] Queue count: {self.arm_command_count}")
                    except ValueError:
                        pass
        except Exception as e:
            print(f"[Bridge] Parse error for '{msg}': {e}")

    def enable_motors(self):
        """Send the enable motors command (S8 E0)."""
        return self.send("S8 E0")

    def disable_motors(self):
        """Send the disable/relax motors command (S8 E1)."""
        return self.send("S8 E1")

    def stop_arm(self):
        """Send emergency stop (S13 N1)."""
        return self.send("S13 N1")

    def move_to(self, x, y, z, trusted=False):
        """Send a move command."""
        cmd = f"G0 X{x} Y{y} Z{z}"
        return self.send(cmd, trusted=trusted)

    def send_gcode_batch(self, gcode_commands):
        """
        Send G-code using the server's flow control — matching
        the GUI's send_Image_command exactly.
        """
        if not gcode_commands:
            return True

        queue = list(gcode_commands)
        total = len(queue)
        sent = 0
        self.violation = None
        self.abort = False
        print(f"[Bridge] Sending {total} G-code commands with flow control...")

        # Start query mode
        self.send_g_code_state = False
        self.arm_command_count = 0
        self.send("S12 K1")

        timeout_start = time.time()

        while queue:
            if self.send_g_code_state and self.arm_command_count < 50:
                send_num = 50 - self.arm_command_count
                if len(queue) < send_num:
                    send_num = len(queue)
                for _ in range(send_num):
                    cmd = queue.pop(0)
                    if self.abort or not self.send(cmd):
                        queue.clear()
                        break
                    sent += 1
                print(f"[Bridge] Sent batch: {sent}/{total} (queue was {self.arm_command_count})")
                # Don't reset send_g_code_state — let the server's
                # next response drive it, just like the GUI does
                self.send_g_code_state = False
            else:
                time.sleep(0.01)

            if time.time() - timeout_start > 600:
                print(f"[Bridge] Timeout at {sent}/{total}")
                break

        # Wait for queue to drain before ending
        print(f"[Bridge] All commands sent, waiting for queue to drain...")
        drain_start = time.time()
        self.send_g_code_state = False
        self.send("S12 K1")
        while time.time() - drain_start < 300:
            if self.send_g_code_state and self.arm_command_count == 0:
                break
            time.sleep(0.1)

        self.send("S12 K0")
        print(f"[Bridge] Drawing complete: {sent}/{total}")
        return sent == total

# Global client instance
freenove = FreenoveClient()

# ════════════════════════════════════════════════════════════════════
# LED & BUZZER — PERSONALITY MODULE
# ════════════════════════════════════════════════════════════════════

# Periwinkle (girlfriend's favorite) — the signature color
PERIWINKLE = (121, 109, 192)
BRIGHT_ORANGE = (255, 102, 0)
DRAWING_BLUE = (7, 9, 161)
ERROR_RED = (179, 33, 30)
SUCCESS_GREEN = (53, 208, 27)

# Musical notes (Hz)
C4, D4, E4, F4, G4, A4, B4 = 262, 294, 330, 349, 392, 440, 494
C5, D5, E5 = 523, 587, 659

def set_led(r, g, b, mode=1):
    """Set LED color. Mode: 1=solid, 2=breathing, 3=rainbow, 4=chase."""
    freenove.send(f"S1 M{mode} R{r} G{g} B{b}")

def buzzer_on(freq):
    freenove.send(f"S2 D{freq}")

def buzzer_off():
    freenove.send("S2 D0")

def play_note(freq, duration=0.15):
    buzzer_on(freq)
    time.sleep(duration)
    buzzer_off()
    time.sleep(0.03)

def play_completion_jingle():
    """Happy ascending jingle when drawing is done."""
    def _play():
        time.sleep(0.3)
        play_note(E4, 0.12)
        play_note(G4, 0.12)
        play_note(B4, 0.12)
        play_note(E5, 0.25)
        time.sleep(0.1)
        play_note(D5, 0.12)
        play_note(E5, 0.35)
    threading.Thread(target=_play, daemon=True).start()

def play_startup_jingle():
    """Gentle startup sound."""
    def _play():
        play_note(C4, 0.15)
        play_note(E4, 0.15)
        play_note(G4, 0.25)
    threading.Thread(target=_play, daemon=True).start()

def play_error_sound():
    """Descending sad tone."""
    def _play():
        play_note(E4, 0.2)
        play_note(C4, 0.3)
    threading.Thread(target=_play, daemon=True).start()

def play_receive_beep():
    """Quick acknowledgment beep when job is received."""
    def _play():
        play_note(A4, 0.08)
        play_note(E5, 0.08)
    threading.Thread(target=_play, daemon=True).start()

def status_idle():
    """Periwinkle breathing — default resting state."""
    set_led(*PERIWINKLE, mode=4)

def status_receiving():
    """Bright orange solid — processing incoming job."""
    set_led(*BRIGHT_ORANGE, mode=1)
    play_receive_beep()

def status_drawing():
    """Blue loading circle — actively drawing."""
    set_led(*DRAWING_BLUE, mode=2)

def status_complete():
    """Periwinkle solid + completion jingle."""
    set_led(*PERIWINKLE, mode=1)
    play_completion_jingle()

def status_error():
    """Flashing red."""
    set_led(*ERROR_RED, mode=3)
    play_error_sound()
    # Return to idle after a few seconds
    def _return():
        time.sleep(4)
        status_idle()
    threading.Thread(target=_return, daemon=True).start()

def status_calibrating():
    """Soft white while adjusting Z height."""
    set_led(180, 180, 200, mode=1)

# ════════════════════════════════════════════════════════════════════
# IMAGE PROCESSING (exact copy of GUI pipeline)
# ════════════════════════════════════════════════════════════════════

def map_value(value, from_low, from_high, to_low, to_high):
    """Linear map, matching the GUI's map() function."""
    return round((to_high - to_low) * (value - from_low) / (from_high - from_low) + to_low, 1)


def process_image_to_contours(image_bytes, threshold=DEFAULT_THRESHOLD,
                               gauss=DEFAULT_GAUSS, sharpen=DEFAULT_SHARPEN):
    """
    Run the exact same OpenCV pipeline as the Freenove GUI:
    raw image → resize to canvas → grayscale → threshold → blur → sharpen → contour
    Returns (contours_data, canvas_size).
    """
    # Decode image
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image")

    CANVAS_WIDTH, CANVAS_HEIGHT = canvas_size()

    # Resize to fit canvas (matching GUI's import logic)
    white_image = np.zeros((CANVAS_HEIGHT, CANVAS_WIDTH, 3), dtype=np.uint8)
    white_image[:, :, :] = [255, 255, 255]

    img_h, img_w = img.shape[:2]
    if img_h <= CANVAS_HEIGHT and img_w <= CANVAS_WIDTH:
        center = ((CANVAS_HEIGHT - img_h) // 2, (CANVAS_WIDTH - img_w) // 2)
        white_image[center[0]:center[0] + img_h, center[1]:center[1] + img_w] = img
    else:
        scale = min((CANVAS_HEIGHT - 2) / img_h, (CANVAS_WIDTH - 2) / img_w)
        new_h = int(scale * img_h)
        new_w = int(scale * img_w)
        resized = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
        center = ((CANVAS_HEIGHT - new_h) // 2, (CANVAS_WIDTH - new_w) // 2)
        white_image[center[0]:center[0] + new_h, center[1]:center[1] + new_w] = resized

    raw_img = white_image.copy()

    # Grayscale
    gray = cv2.cvtColor(raw_img, cv2.COLOR_BGR2GRAY)

    # Ensure gauss is odd
    if gauss % 2 == 0:
        gauss += 1

    # Binary threshold + Gaussian blur + sharpen
    _, binary = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
    blurred = cv2.GaussianBlur(binary, (gauss, gauss), 0, 0)
    kernel = np.array([[0, -1, 0], [-1, sharpen, -1], [0, -1, 0]], np.float32)
    sharpened = cv2.filter2D(blurred, -1, kernel=kernel)

    # Find contours (matching GUI: RETR_TREE + CHAIN_APPROX_SIMPLE)
    contours, hierarchy = cv2.findContours(sharpened, cv2.RETR_TREE, cv2.CHAIN_APPROX_SIMPLE)

    return contours, (CANVAS_WIDTH, CANVAS_HEIGHT)


def render_text_to_image(text, font_name=None, font_size=80):
    """
    Render text as a black-on-white image using Pillow,
    then return as image bytes for the same contour pipeline.
    """
    CANVAS_WIDTH, CANVAS_HEIGHT = canvas_size()

    # Create a white canvas
    img = Image.new("RGB", (CANVAS_WIDTH, CANVAS_HEIGHT), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Try to load the specified font, fall back to default
    font = None
    if font_name:
        # Try with and without .ttf extension
        names_to_try = [font_name, f"{font_name}.ttf", f"{font_name}.otf"]
        search_dirs = [
            "/home/tallergiraffe/fonts",
            "/usr/share/fonts/truetype",
            "/usr/share/fonts",
        ]
        for name in names_to_try:
            for directory in search_dirs:
                path = os.path.join(directory, name)
                if os.path.exists(path):
                    try:
                        font = ImageFont.truetype(path, font_size)
                        print(f"[Bridge] Loaded font: {path}")
                        break
                    except:
                        continue
            if font:
                break


    if font is None:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_size)
        except:
            font = ImageFont.load_default()

    # Get text bounding box and center it
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (CANVAS_WIDTH - text_w) // 2
    y = (CANVAS_HEIGHT - text_h) // 2
    draw.text((x, y), text, fill=(0, 0, 0), font=font)

    # Convert to bytes
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def contours_to_strokes(contours, canvas_size):
    """
    Contours (canvas pixels) → strokes in arm mm, clipped to the sand pit.
    Contour 0 is the image's outer frame and is skipped, as in the GUI.
    """
    strokes = []
    for i in range(1, len(contours)):
        pts = [px_to_mm(px, py, canvas_size) for px, py in (c[0] for c in contours[i])]
        if len(pts) < 2:
            continue
        pts.append(pts[0])  # close the contour
        strokes.extend(boundary.clip_stroke(pts))
    return strokes


def strokes_to_gcode(strokes, pen_up_height=DEFAULT_PEN_UP_HEIGHT):
    """
    Strokes (arm mm) → G-code. Pen-up travel that would leave the pit
    (e.g. lobe to lobe across the notch) lifts to the safe Z first.
    """
    z_axis = HOME_POSITION[2]  # drawing Z height
    z_up = round(z_axis + pen_up_height, 1)
    safe_z = boundary.safe_z
    commands = []
    last = (HOME_POSITION[0], HOME_POSITION[1])

    def travel(to):
        start, end = (last[0], last[1], z_up), (to[0], to[1], z_up)
        if boundary.check_move(start, end):
            # Can't go straight (e.g. across the notch): lift over the rim.
            a = boundary.lift_point(last[0], last[1], z_up)
            b = boundary.lift_point(to[0], to[1], z_up)
            if a is None or b is None:
                raise ValueError(f"no reachable spot to lift over the rim near "
                                 f"X{(last if a is None else to)[0]} Y{(last if a is None else to)[1]}")
            commands.append(f"G0 X{a[0]} Y{a[1]} Z{z_up}")
            commands.append(f"G0 X{a[0]} Y{a[1]} Z{safe_z}")
            commands.append(f"G0 X{b[0]} Y{b[1]} Z{safe_z}")
            commands.append(f"G0 X{b[0]} Y{b[1]} Z{z_up}")
        commands.append(f"G0 X{to[0]} Y{to[1]} Z{z_up}")

    commands.append(f"G0 X{last[0]} Y{last[1]} Z{z_up}")
    for stroke in strokes:
        travel(stroke[0])
        for x, y in stroke:
            commands.append(f"G0 X{x} Y{y} Z{z_axis}")
        last = stroke[-1]
        commands.append(f"G0 X{last[0]} Y{last[1]} Z{z_up}")

    # Return to home (drawing area), fold happens separately after
    travel((HOME_POSITION[0], HOME_POSITION[1]))
    return commands


def preflight(gcode):
    """Simulate every move against the boundary before touching the arm."""
    pos = None
    for cmd in gcode:
        target = FreenoveClient._parse_move(cmd, pos)
        if target is None or None in target:
            continue
        reason = boundary.check_move(pos, target)
        if reason:
            return reason
        pos = target
    return None


def render_pit_preview(strokes=None, contours=None, canvas=None):
    """
    Preview image shaped like the real pit: sand-colored kidney, the area
    outside it dimmed, and the (clipped) strokes that will actually be drawn.
    """
    size = canvas or canvas_size()
    w, h = size
    img = np.full((h, w, 3), 235, dtype=np.uint8)            # outside the pit
    poly = np.array([mm_to_px(x, y, size) for x, y in boundary.polygon], np.int32)
    cv2.fillPoly(img, [poly], (214, 232, 242))                # sand (BGR)
    if contours is not None:
        cv2.drawContours(img, contours, -1, (200, 200, 200), 1)  # full image, faint
    for stroke in strokes or []:
        pts = np.array([mm_to_px(x, y, size) for x, y in stroke], np.int32)
        cv2.polylines(img, [pts], False, (40, 40, 40), 2, cv2.LINE_AA)
    cv2.polylines(img, [poly], True, (60, 90, 140), 3, cv2.LINE_AA)  # rim
    _, buf = cv2.imencode(".png", img)
    return buf.tobytes()


# ════════════════════════════════════════════════════════════════════
# FLASK HTTP ENDPOINTS
# ════════════════════════════════════════════════════════════════════

@app.route("/status", methods=["GET"])
def get_status():
    """Get robot connection status."""
    return jsonify({
        "state": "idle" if freenove.connected else "offline",
        "connected": freenove.connected,
        "queue_length": 0
    })


@app.route("/connect", methods=["POST"])
def connect_arm():
    """Connect to the Freenove server."""
    if freenove.connected:
        return jsonify({"success": True, "message": "Already connected"})
    success = freenove.connect()
    if success:
        return jsonify({"success": True, "message": "Connected"})
    else:
        return jsonify({"success": False, "message": "Connection failed"}), 500


@app.route("/load", methods=["POST"])
def load_motors():
    """Enable motors."""
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    freenove.enable_motors()
    return jsonify({"success": True})


@app.route("/relax", methods=["POST"])
def relax_motors():
    """Disable/relax motors."""
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    freenove.disable_motors()
    return jsonify({"success": True})


@app.route("/stop", methods=["POST"])
def stop_arm():
    """Emergency stop."""
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    freenove.abort = True
    freenove.stop_arm()
    return jsonify({"success": True})


@app.route("/preview", methods=["POST"])
def preview_image():
    """
    Process an image and return a contour preview (no drawing).
    Expects multipart form: image file + optional params.
    """
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400

    image_bytes = request.files["image"].read()
    threshold = int(request.form.get("threshold", DEFAULT_THRESHOLD))
    gauss = int(request.form.get("gauss", DEFAULT_GAUSS))
    sharpen = int(request.form.get("sharpen", DEFAULT_SHARPEN))

    try:
        contours, canvas_size = process_image_to_contours(
            image_bytes, threshold, gauss, sharpen
        )
        strokes = contours_to_strokes(contours, canvas_size)
        preview = render_pit_preview(strokes, contours, canvas_size)
        return send_file(io.BytesIO(preview), mimetype="image/png")
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/draw", methods=["POST"])
def draw():
    """
    Process an image or text and send drawing commands to the arm.
    
    For images: multipart form with 'image' file + optional params
    For text: JSON body with 'text', optional 'font_name', 'font_size'
    
    Both go through the same contour → G-code pipeline.
    """
    if not freenove.connected:
        return jsonify({"error": "Not connected to arm"}), 400

    job_id = str(uuid.uuid4())[:8]
    source = "image"
    label = "Drawing"

    try:
        # Determine input type
        if request.content_type and "multipart" in request.content_type:
            # Image upload
            if "image" not in request.files:
                return jsonify({"error": "No image provided"}), 400

            image_bytes = request.files["image"].read()
            threshold = int(request.form.get("threshold", DEFAULT_THRESHOLD))
            gauss = int(request.form.get("gauss", DEFAULT_GAUSS))
            sharpen = int(request.form.get("sharpen", DEFAULT_SHARPEN))
            pen_up_height = int(request.form.get("pen_up_height", DEFAULT_PEN_UP_HEIGHT))
            label = request.form.get("label", "Image Drawing")
            source = "image"

        elif request.is_json:
            # Text input
            data = request.get_json()
            text = data.get("text", "")
            if not text:
                return jsonify({"error": "No text provided"}), 400

            font_name = data.get("font_name", None)
            font_size = data.get("font_size", 80)
            threshold = data.get("threshold", DEFAULT_THRESHOLD)
            gauss = data.get("gauss", DEFAULT_GAUSS)
            sharpen = data.get("sharpen", DEFAULT_SHARPEN)
            pen_up_height = data.get("pen_up_height", DEFAULT_PEN_UP_HEIGHT)
            label = text
            source = "text"

            # Render text to image
            image_bytes = render_text_to_image(text, font_name, font_size)
        else:
            return jsonify({"error": "Invalid content type"}), 400

        # Process image → contours
        contours, canvas_size = process_image_to_contours(
            image_bytes, threshold, gauss, sharpen
        )

        # Convert contours → clipped strokes → G-code
        strokes = contours_to_strokes(contours, canvas_size)
        if not strokes:
            return jsonify({"error": "Nothing to draw inside the pit — try adjusting threshold"}), 400
        gcode = strokes_to_gcode(strokes, pen_up_height)

        reason = preflight(gcode)
        if reason:
            return jsonify({"error": f"Blocked by pit boundary: {reason}"}), 400

        # Track the job
        with jobs_lock:
            jobs[job_id] = {
                "status": "queued",
                "created_at": datetime.now().isoformat(),
                "label": label,
                "source": source,
                "gcode_count": len(gcode),
            }

        # Send G-code in background thread
        def execute_drawing():
            with jobs_lock:
                jobs[job_id]["status"] = "drawing"
            status_drawing()
            freenove.enable_motors()
            time.sleep(0.5)
            freenove.send("S10 F1")
            time.sleep(2)

            success = freenove.send_gcode_batch(gcode)

            # Park at the camera view position and photograph the result.
            # Motors stay enabled: relaxing up there would drop the arm onto the drawing.
            print("[Bridge] Re-homing before parking...")
            freenove.send("S10 F1")
            time.sleep(1.5)
            park_at_view()
            photo = take_photo(job_id) if success else None

            with jobs_lock:
                jobs[job_id]["photo"] = bool(photo)
                jobs[job_id]["status"] = "completed" if success else "failed"
                if freenove.violation:
                    jobs[job_id]["error"] = f"Blocked by pit boundary: {freenove.violation}"
            if success:
                status_complete()
                def _to_idle():
                    time.sleep(5)
                    status_idle()
                threading.Thread(target=_to_idle, daemon=True).start()
            else:
                status_error()

        status_receiving()

        thread = threading.Thread(target=execute_drawing, daemon=True)
        thread.start()

        return jsonify({
            "accepted": True,
            "job_id": job_id,
            "gcode_count": len(gcode),
        })

    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


def park_at_view():
    """Lift clear of the rim at home, then go to the camera view position."""
    print("[Bridge] Moving to camera view position...")
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], HOME_POSITION[2] + DEFAULT_PEN_UP_HEIGHT)
    time.sleep(3)
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], boundary.safe_z)  # clear the rim
    time.sleep(2)
    vx, vy, vz = view_position()
    freenove.move_to(vx, vy, vz)
    time.sleep(4)


def take_photo(name):
    """Grab a frame from camera_stream.py and save it as photos/<name>.jpg."""
    import urllib.request
    os.makedirs(PHOTO_DIR, exist_ok=True)
    time.sleep(2.5)  # let autofocus settle after the move
    try:
        with urllib.request.urlopen(CAMERA_SNAPSHOT_URL, timeout=5) as r:
            data = r.read()
        path = os.path.join(PHOTO_DIR, f"{name}.jpg")
        with open(path, "wb") as f:
            f.write(data)
        print(f"[Bridge] Saved photo {path}")
        return path
    except Exception as e:
        print(f"[Bridge] Photo failed: {e}")
        return None


@app.route("/job/<job_id>/photo", methods=["GET"])
def get_job_photo(job_id):
    path = os.path.join(PHOTO_DIR, f"{os.path.basename(job_id)}.jpg")
    if not os.path.exists(path):
        return jsonify({"error": "No photo for this job"}), 404
    return send_file(path, mimetype="image/jpeg")


@app.route("/view-position", methods=["GET"])
def get_view_position():
    x, y, z = view_position()
    return jsonify({"x": x, "y": y, "z": z})


@app.route("/view-position", methods=["POST"])
def set_view_position():
    """Save the pen's current position as the camera view / rest position."""
    if freenove.pos is None:
        return jsonify({"error": "Position unknown"}), 400
    cfg = load_robot_config()
    cfg["view_position"] = list(freenove.pos)
    save_robot_config(cfg)
    return get_view_position()


@app.route("/job/<job_id>", methods=["GET"])
def get_job_status(job_id):
    """Get the status of a drawing job."""
    with jobs_lock:
        job = jobs.get(job_id)
    if not job:
        return jsonify({"error": "Job not found"}), 404
    return jsonify({
        "job_id": job_id,
        "status": job["status"],
        "label": job.get("label", ""),
        "source": job.get("source", ""),
        "gcode_count": job.get("gcode_count", 0),
        "error": job.get("error"),
        "photo": job.get("photo", False),
    })


@app.route("/move", methods=["POST"])
def move():
    """Move the arm to a specific position."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    data = request.get_json()
    position = data.get("position", "home")
    if position == "home":
        freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], HOME_POSITION[2])
    elif position == "overview":
        freenove.move_to(HOME_POSITION[0], HOME_POSITION[1],
                         HOME_POSITION[2] + DEFAULT_PEN_UP_HEIGHT)
    elif position == "view":
        threading.Thread(target=park_at_view, daemon=True).start()
    return jsonify({"accepted": True})


@app.route("/home", methods=["POST"])
def go_home():
    """Send arm to home position."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], HOME_POSITION[2])
    return jsonify({"success": True})

@app.route("/set-z", methods=["POST"])
def set_z_height():
    global HOME_POSITION
    data = request.get_json()
    new_z = data.get("z_height", HOME_POSITION[2])
    HOME_POSITION[2] = float(new_z)
    if freenove.connected:
        status_calibrating()
        freenove.send(f"G0 X0 Y200 Z{HOME_POSITION[2]}")
    print(f"[Bridge] Z height updated to {HOME_POSITION[2]}mm")
    return jsonify({"success": True, "z_height": HOME_POSITION[2]})

# ════════════════════════════════════════════════════════════════════
# SAND PIT BOUNDARY + CALIBRATION
# ════════════════════════════════════════════════════════════════════

calibration_points = []  # rim points recorded while jogging, in order


@app.route("/boundary", methods=["GET"])
def get_boundary():
    d = boundary.to_dict()
    w, h = canvas_size()
    d["canvas"] = {"width": w, "height": h}
    return jsonify(d)


@app.route("/boundary", methods=["POST"])
def set_boundary():
    """Replace the outline: {"polygon": [[x, y], ...], "smooth": bool}."""
    data = request.get_json() or {}
    try:
        boundary.set_polygon(data["polygon"], smooth=bool(data.get("smooth", False)))
    except (KeyError, ValueError, TypeError) as e:
        return jsonify({"error": str(e)}), 400
    return get_boundary()


@app.route("/boundary/settings", methods=["POST"])
def set_boundary_settings():
    """{"safe_z": float, "margin_mm": float} — either may be omitted."""
    data = request.get_json() or {}
    boundary.update_settings(data.get("safe_z"), data.get("margin_mm"))
    return get_boundary()


@app.route("/boundary/reset", methods=["POST"])
def reset_boundary():
    boundary.reset()
    return get_boundary()


@app.route("/preview-text", methods=["POST"])
def preview_text():
    """Same as /draw for text, but returns the pit preview PNG instead of drawing."""
    data = request.get_json() or {}
    text = data.get("text", "")
    if not text:
        return jsonify({"error": "No text provided"}), 400
    try:
        image_bytes = render_text_to_image(text, data.get("font_name"), data.get("font_size", 80))
        contours, size = process_image_to_contours(
            image_bytes,
            data.get("threshold", DEFAULT_THRESHOLD),
            data.get("gauss", DEFAULT_GAUSS),
            data.get("sharpen", DEFAULT_SHARPEN),
        )
        strokes = contours_to_strokes(contours, size)
        return send_file(io.BytesIO(render_pit_preview(strokes, contours, size)), mimetype="image/png")
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/position", methods=["GET"])
def get_position():
    pos = freenove.pos
    return jsonify({
        "known": pos is not None,
        "x": pos[0] if pos else None,
        "y": pos[1] if pos else None,
        "z": pos[2] if pos else None,
        "inside": boundary.contains(pos[0], pos[1]) if pos else None,
        "points": calibration_points,
    })


@app.route("/calibrate/start", methods=["POST"])
def calibrate_start():
    """Home the arm and park the pen just above the sand at the home point."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    status_calibrating()
    freenove.enable_motors()
    time.sleep(0.5)
    freenove.send("S10 F1")
    time.sleep(2)
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1],
                     HOME_POSITION[2] + DEFAULT_PEN_UP_HEIGHT, trusted=True)
    calibration_points.clear()
    return get_position()


@app.route("/calibrate/jog", methods=["POST"])
def calibrate_jog():
    """
    Nudge the pen by {"dx", "dy", "dz"} mm, or go to absolute {"x", "y", "z"}.
    Ignores the pit boundary (we're finding it) but never the arm's reach.
    """
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    if freenove.pos is None:
        return jsonify({"error": "Position unknown — start calibration first"}), 400
    data = request.get_json() or {}
    x, y, z = freenove.pos
    x = float(data.get("x", x + float(data.get("dx", 0))))
    y = float(data.get("y", y + float(data.get("dy", 0))))
    z = float(data.get("z", z + float(data.get("dz", 0))))
    x, y, z = round(x, 1), round(y, 1), round(z, 1)
    if not reachable(x, y, z) or (x * x + y * y) ** 0.5 < 82:
        return jsonify({"error": f"X{x} Y{y} Z{z} is out of the arm's reach"}), 400
    freenove.move_to(x, y, z, trusted=True)
    return get_position()


@app.route("/calibrate/record", methods=["POST"])
def calibrate_record():
    """Record the pen's current XY as the next rim point."""
    if freenove.pos is None:
        return jsonify({"error": "Position unknown"}), 400
    calibration_points.append([freenove.pos[0], freenove.pos[1]])
    return get_position()


@app.route("/calibrate/undo", methods=["POST"])
def calibrate_undo():
    if calibration_points:
        calibration_points.pop()
    return get_position()


@app.route("/calibrate/save", methods=["POST"])
def calibrate_save():
    """Save recorded rim points as the new (smoothed) boundary."""
    if len(calibration_points) < 5:
        return jsonify({"error": "Record at least 5 rim points first"}), 400
    boundary.set_polygon(list(calibration_points), smooth=True)
    return get_boundary()


@app.route("/calibrate/finish", methods=["POST"])
def calibrate_finish():
    """Lift clear of the rim and park at the camera view position (motors stay on)."""
    if freenove.connected and freenove.pos is not None:
        x, y, _ = freenove.pos
        if reachable(x, y, boundary.safe_z):
            freenove.move_to(x, y, boundary.safe_z, trusted=True)
            time.sleep(2)
        vx, vy, vz = view_position()
        freenove.move_to(vx, vy, vz, trusted=True)
        time.sleep(3)
    status_idle()
    return get_position()

# ════════════════════════════════════════════════════════════════════
# STARTUP
# ════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("=" * 60)
    print("SandBot Bridge Server")
    print("=" * 60)

    # Auto-connect to Freenove server on startup
    print("[Bridge] Connecting to Freenove server...")
    if freenove.connect():
        print("[Bridge] Connected!")
        time.sleep(1)
        play_startup_jingle()
        status_idle()
        print("[Bridge] LED set to periwinkle breathing (idle)")
    else:
        print("[Bridge] WARNING: Could not connect to Freenove server.")
        print("[Bridge] Make sure main.py is running first.")
        print("[Bridge] You can connect later via POST /connect")

    print(f"[Bridge] Starting HTTP server on port 8080...")
    print(f"[Bridge] iOS app should target: http://100.95.15.84:8080")
    print("=" * 60)

    app.run(host="0.0.0.0", port=8080, debug=False)
