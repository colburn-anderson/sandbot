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
  5. Answers resent requests once (see RESENT REQUESTS) — the app resends
     whatever got no answer while the Pi's Wi-Fi was hopping

Run this ON THE PI alongside main.py:
  sudo python sandbot_bridge.py
"""

import os
import math
import io
import sys
import time
import json
import uuid
import socket
import functools
import threading
import traceback
from collections import OrderedDict
from datetime import datetime
from flask import Flask, request, jsonify, send_file
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from boundary import Boundary, reachable

# systemd pipes stdout, which Python block-buffers: without this our
# [Bridge] log lines never reach journalctl.
sys.stdout.reconfigure(line_buffering=True)

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
HOME_POSITION = [0.0, 200.0, 58.5]  # X, Y, Z — Z (pen-down height) is overridden from robot_config.json below
# Resting pose: Freenove's homing (S10) ends with the arm tucked up high
# (joint zero angles ≈ X0 Y95 Z262). We rest there with motors off. The old
# fold target (0, 50, 130) is outside the arm's joint limits and was always
# silently rejected by the arm server.

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


# Pen-down height survives restarts (paper vs notebook changes it).
HOME_POSITION[2] = float(load_robot_config().get("draw_z", HOME_POSITION[2]))
boundary.surface_z = HOME_POSITION[2]  # rim crossing height follows the surface

# Homing starts with a blind kick of a few cm, so lift at least this far
# above the drawing surface before homing.
HOMING_LIFT_MM = 60.0

# ── IMAGE CANVAS SIZE (derived from the pit's bounding box) ─────────
def canvas_size():
    min_x, min_y, max_x, max_y = boundary.bbox()
    return (int(round((max_x - min_x) / MM_PER_PX)),
            int(round((max_y - min_y) / MM_PER_PX)))


def px_to_mm(px, py, size):
    """Canvas pixel → arm (x, y) in mm."""
    min_x, min_y, max_x, max_y = boundary.bbox()
    w, h = size
    return (round(float(min_x + (max_x - min_x) * px / w), 1),
            round(float(max_y - (max_y - min_y) * py / h), 1))


def mm_to_px(x, y, size):
    min_x, min_y, max_x, max_y = boundary.bbox()
    w, h = size
    return ((x - min_x) / (max_x - min_x) * w,
            (max_y - y) / (max_y - min_y) * h)

# ── JOB TRACKING ────────────────────────────────────────────────────
jobs = {}  # job_id -> {status, created_at, label, source, ...}
jobs_lock = threading.Lock()

# One drawing at a time. Held from the moment a job is accepted until the arm
# has rested; while held, every other arm-moving endpoint refuses (409).
robot_busy = threading.Lock()
current_job = {"id": None, "label": None}


def refuse_while_busy(fn):
    """Decorator: 409 instead of moving the arm while a drawing is running."""
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        if robot_busy.locked():
            return jsonify({
                "success": False,
                "error": f"Robot is busy drawing \"{current_job['label']}\" — wait for it to finish.",
                "busy": True,
                "job_id": current_job["id"],
                "z_height": HOME_POSITION[2],
            }), 409
        return fn(*args, **kwargs)
    return wrapper


# ── RESENT REQUESTS ─────────────────────────────────────────────────
# The Pi's Wi-Fi drops for a second or two each time it hops between the
# router's two radios, so the app quietly resends any request that got no
# answer. Requests that change something carry an X-Request-ID that stays the
# same on every resend, and a repeat gets the first reply back instead of
# running again: a drawing is never drawn twice, a jog never moves twice.
# Drawing replies are also kept on disk in case the bridge restarts while the
# app is still resending.
RESENDS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "recent_requests.json")
MAX_REMEMBERED_REQUESTS = 100
replies = OrderedDict()  # request id -> {"done": Event, "reply": (body, status) or None, "persist": bool}
replies_lock = threading.Lock()


def load_saved_replies():
    try:
        with open(RESENDS_FILE) as f:
            saved = json.load(f)
        for request_id, (body, status) in saved.items():
            done = threading.Event()
            done.set()
            replies[request_id] = {"done": done, "reply": (body.encode(), int(status)), "persist": True}
    except FileNotFoundError:
        pass
    except (OSError, ValueError, TypeError, AttributeError) as e:
        print(f"[Bridge] Ignoring unreadable {RESENDS_FILE}: {e}")


def save_replies():
    try:
        with replies_lock:
            keep = {rid: [e["reply"][0].decode(), e["reply"][1]]
                    for rid, e in replies.items() if e["persist"] and e["reply"]}
            with open(RESENDS_FILE + ".tmp", "w") as f:
                json.dump(keep, f)
            os.replace(RESENDS_FILE + ".tmp", RESENDS_FILE)
    except OSError as e:
        print(f"[Bridge] Couldn't save recent requests: {e}")


load_saved_replies()


def idempotent(fn=None, *, persist=False):
    """
    Decorator: a request resent with the same X-Request-ID gets the first
    reply instead of running again. Requests without an ID run as usual.
    `persist` keeps the replies across bridge restarts.
    """
    if fn is None:
        return functools.partial(idempotent, persist=persist)

    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        request_id = request.headers.get("X-Request-ID")
        if not request_id:
            return fn(*args, **kwargs)
        # Take in the whole request before claiming its ID, so a half-arrived
        # copy from a dropped connection can't hold up the resend.
        request.get_data(parse_form_data=True)
        while True:
            with replies_lock:
                entry = replies.get(request_id)
                first = entry is None
                if first:
                    entry = replies[request_id] = {"done": threading.Event(), "reply": None,
                                                   "persist": persist}
                    while len(replies) > MAX_REMEMBERED_REQUESTS:
                        replies.popitem(last=False)
            if first:
                break
            # Seen it before: wait for the first copy to finish, then give the same answer.
            entry["done"].wait(timeout=60)
            if entry["reply"] is not None:
                print(f"[Bridge] Resent {request.path} ({request_id[:8]}): answered from the first copy")
                body, status = entry["reply"]
                return app.response_class(body, status=status, mimetype="application/json")
            if not entry["done"].is_set():
                return jsonify({"error": "The robot is still working on this request"}), 503
            # The first copy crashed without an answer (and forgot its ID): run this one.

        try:
            response = app.make_response(fn(*args, **kwargs))
        except Exception:
            with replies_lock:
                replies.pop(request_id, None)
            entry["done"].set()
            raise
        entry["reply"] = (response.get_data(), response.status_code)
        entry["done"].set()
        if persist:
            save_replies()
        return response
    return wrapper


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
        self.motors_on = False   # we enabled the steppers (and haven't relaxed them)
        self.homed = False       # S10 sent since motors were enabled

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
            self.homed = True
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
        self.motors_on = True
        return self.send("S8 E0")

    def disable_motors(self):
        """Send the disable/relax motors command (S8 E1)."""
        self.motors_on = False
        self.homed = False
        self.pos = None
        return self.send("S8 E1")

    def home_high(self):
        """
        Home (S10) with the pen lifted. Homing starts with a blind ~7.5°/5°
        kick of motors 2 and 3 (a few cm of pen travel) before searching for
        the sensors, so it must never start near the surface.
        """
        if self.pos is not None:
            x, y, z = self.pos
            lift_z = max(boundary.safe_z, HOME_POSITION[2] + HOMING_LIFT_MM)
            if z < lift_z:
                if reachable(x, y, lift_z):
                    self.move_to(x, y, lift_z, trusted=True)
                    time.sleep(2)
                else:
                    print(f"[Bridge] WARNING: can't lift at X{x} Y{y} before homing")
        # pos None = resting/tucked pose after homing or relax, already high.
        self.send("S10 F1")
        time.sleep(2.5)

    def ensure_ready(self):
        """Enable motors and home (safely) once, so a lone move actually moves."""
        if not self.motors_on:
            self.enable_motors()
            time.sleep(0.5)
        if not self.homed:
            self.home_high()

    def rest(self):
        """Tuck the arm up (home, high) and turn the motors off — safe to leave 24/7."""
        print("[Bridge] Resting: homing up high, then unloading motors")
        self.home_high()
        self.disable_motors()

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
        self.violation = None  # (abort is reset when the job starts, so an early Stop counts)
        print(f"[Bridge] Sending {total} G-code commands with flow control...")

        # Start query mode
        self.send_g_code_state = False
        self.arm_command_count = 0
        self.send("S12 K1")

        timeout_start = time.time()

        while queue:
            if self.abort:
                print(f"[Bridge] Stop requested at {sent}/{total}")
                queue.clear()
                break
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

            # Safety net only: generous enough for the longest allowed drawing.
            if time.time() - timeout_start > (MAX_DRAW_MINUTES * 2 + 10) * 60:
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


def image_ink(image_bytes):
    """
    Picture → "ink" image: dark-on-white gray at 2x canvas resolution, where
    darkness = how different each pixel's colour is from the background
    (median colour of the picture's border). Works for any colours: dark on
    light, white on blue, teal on white, blue-grey on light grey.
    """
    nparr = np.frombuffer(image_bytes, np.uint8)
    color = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if color is None:
        raise ValueError("Could not decode image")
    lab = cv2.cvtColor(color, cv2.COLOR_BGR2LAB).astype(np.float32)
    border = np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])
    background = np.median(border, axis=0)
    ink = np.linalg.norm(lab - background, axis=2)
    ink_scale = max(float(np.percentile(ink, 99)), 25.0)  # don't amplify noise on blank pictures
    gray = (255 - np.clip(ink / ink_scale * 255, 0, 255)).astype(np.uint8)

    # Work at 2x canvas resolution, scaling small images up and big ones down.
    w, h = canvas_size()
    gh, gw = gray.shape
    f = 2 * min((w - 8) / gw, (h - 8) / gh)
    gray = cv2.resize(gray, (max(1, int(gw * f)), max(1, int(gh * f))),
                      interpolation=cv2.INTER_AREA if f < 1 else cv2.INTER_CUBIC)
    return cv2.copyMakeBorder(gray, 8, 8, 8, 8, cv2.BORDER_CONSTANT, value=255)


def line_binary(gray, threshold, gauss, sharpen):
    """Ink image → pure black lines on white, with the user's filter settings."""
    if gauss % 2 == 0:
        gauss += 1
    _, binary = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
    # Close small gaps in the (dark) lines so they trace as one piece.
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    blurred = cv2.GaussianBlur(binary, (gauss, gauss), 0, 0)
    kernel = np.array([[0, -1, 0], [-1, sharpen, -1], [0, -1, 0]], np.float32)
    sharpened = cv2.filter2D(blurred, -1, kernel=kernel)
    # Back to pure black/white: findContours treats any non-zero pixel as
    # background, so a thin line whose middle the blur lightened even
    # slightly would otherwise vanish or break into dashes.
    _, sharpened = cv2.threshold(sharpened, 127, 255, cv2.THRESH_BINARY)
    return sharpened


def auto_image_settings(image_bytes):
    """
    Pick threshold / blur / sharpen for this picture by trying combinations
    and scoring each against the original: the traced lines should sit where
    the picture's lines are (precision), cover all of them (recall), and not
    break into specks. The reference is the picture's own lines found with
    Otsu's automatic threshold.
    """
    gray = image_ink(image_bytes)
    otsu, ref = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    near = np.ones((3, 3), np.uint8)
    ref_near = cv2.dilate(ref, near, iterations=1) > 0
    ref_on = ref > 0
    ref_count = max(int(ref_on.sum()), 1)
    best = None
    thresholds = sorted({int(np.clip(otsu + d, 60, 240)) for d in (-70, -45, -20, 0, 20, 45, 70)})
    for t in thresholds:
        for g in (1, 3, 5):
            for sh in (5, 7, 9):
                cand = line_binary(gray, t, g, sh) == 0          # True = line
                count = int(cand.sum())
                if count == 0:
                    continue
                precision = float((cand & ref_near).sum()) / count
                cand_near = cv2.dilate(cand.astype(np.uint8), near, iterations=1) > 0
                recall = float((ref_on & cand_near).sum()) / ref_count
                f1 = 2 * precision * recall / max(precision + recall, 1e-6)
                n, _, stats, _ = cv2.connectedComponentsWithStats(cand.astype(np.uint8), connectivity=8)
                areas = stats[1:, cv2.CC_STAT_AREA]
                specks = float((areas < 40).sum()) / max(len(areas), 1)
                score = f1 - 0.35 * specks
                # Ties: fewer separate pieces (more connected lines), then the
                # threshold closest to the picture's own (Otsu).
                key = (round(score, 3), -len(areas), -abs(t - otsu))
                if best is None or key > best[0]:
                    best = (key, t, g, sh)
    if best is None:
        return {"threshold": DEFAULT_THRESHOLD, "gauss": DEFAULT_GAUSS, "sharpen": DEFAULT_SHARPEN, "score": 0.0}
    (score, _, _), t, g, sh = best
    return {"threshold": t, "gauss": g, "sharpen": sh, "score": round(score, 3)}


def image_to_contours(image_bytes, threshold=DEFAULT_THRESHOLD, gauss=DEFAULT_GAUSS,
                       sharpen=DEFAULT_SHARPEN, layout=None):
    """
    Image → line outlines in canvas pixels, placed per `layout`.

    Threshold → blur → sharpen → contour, like the Freenove GUI, but:
    - lines are found by how different their colour is from the background
      (median colour of the picture's border), so any colours work: dark on
      light, white on blue, teal on white, blue-grey on light grey,
    - it works at 2x the canvas resolution and closes 1–2 px gaps, so thin
      lines stay continuous instead of breaking into dots,
    - frames (anything spanning nearly the whole picture both ways) are
      dropped, and the result is cropped to the actual drawing,
    - the drawing is scaled to fit the pit, then bent/rotated/moved by
      `layout` (scale 1.0 = fits the pit with a little room).
    `threshold` keeps its meaning: higher picks up fainter lines.
    """
    layout = layout or {}
    w, h = canvas_size()
    sharpened = line_binary(image_ink(image_bytes), threshold, gauss, sharpen)
    contours, _ = cv2.findContours(sharpened, cv2.RETR_TREE, cv2.CHAIN_APPROX_NONE)

    # Drop frames: anything spanning (nearly) the whole picture both ways —
    # the white padding's outline, a drawn border, a leftover background box.
    # Lines that merely run off one edge (e.g. a wave band) are kept.
    ih, iw = sharpened.shape
    keep = []
    for c in contours:
        _, _, bw, bh = cv2.boundingRect(c)
        if bw >= 0.92 * iw and bh >= 0.92 * ih:
            continue
        keep.append(c)
    if not keep:
        return [], (w, h)

    # Crop to the drawing and fit it in the pit.
    allpts = np.vstack([c.reshape(-1, 2) for c in keep])
    x0, y0 = allpts.min(axis=0)
    x1, y1 = allpts.max(axis=0)
    cw, ch = max(float(x1 - x0), 1.0), max(float(y1 - y0), 1.0)
    fit = 0.85 * min(w / cw, h / ch)
    scale = max(0.05, float(layout.get("scale", 1.0) or 1.0))
    return place_contours(keep, origin=((x0 + x1) / 2, (y0 + y1) / 2), local_to_canvas=fit * scale,
                          width_local=cw, layout=layout), (w, h)


TEXT_SUPERSAMPLE = 3   # render text at 3x so thin script hairlines stay solid
SIMPLIFY_MM = 0.3      # drop contour points that change the line by < 0.3 mm


def load_font(font_name, font_size):
    """Find a font by name in ~/fonts or the system fonts; DejaVu Sans fallback."""
    if font_name:
        search_dirs = ["/home/tallergiraffe/fonts", "/usr/share/fonts/truetype", "/usr/share/fonts"]
        for name in (font_name, f"{font_name}.ttf", f"{font_name}.otf"):
            for directory in search_dirs:
                path = os.path.join(directory, name)
                if os.path.exists(path):
                    try:
                        font = ImageFont.truetype(path, font_size)
                        print(f"[Bridge] Loaded font: {path}")
                        return font
                    except OSError:
                        continue
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_size)
    except OSError:
        return ImageFont.load_default()


def place_contours(contours, origin, local_to_canvas, width_local, layout):
    """
    Put traced outlines into the canvas: bend along an arc (layout "curve"),
    rotate (layout "rotation", degrees counter-clockwise on screen), scale,
    and move so `origin` lands on the layout centre. Shared by text and images.

    curve > 0 arches the shape up (∩, follows the top of the pit); curve < 0
    dips it (∪, wraps around the notch); |curve| = 1 bends its full width
    into a half circle. The whole shape bends as one piece, so connected
    script letters stay joined.
    """
    w, h = canvas_size()
    center = layout.get("center")
    cx, cy = (w / 2, h / 2) if center is None else mm_to_px(center[0], center[1], (w, h))
    curve = max(-1.0, min(1.0, float(layout.get("curve", 0) or 0)))
    a = math.radians(float(layout.get("rotation", 0) or 0))
    # Image y points down, so counter-clockwise on screen is this matrix.
    rot = np.array([[math.cos(a), math.sin(a)], [-math.sin(a), math.cos(a)]])
    eps = SIMPLIFY_MM / MM_PER_PX
    placed = []
    for c in contours:
        pts = c.reshape(-1, 2).astype(np.float64) - np.asarray(origin, np.float64)
        if abs(curve) >= 0.02 and width_local > 0:
            radius = width_local / (math.pi * abs(curve))
            u, v = pts[:, 0], pts[:, 1]
            theta = u / radius
            if curve > 0:   # arch: circle centre below the shape
                rho = radius - v
                pts = np.stack([rho * np.sin(theta), radius - rho * np.cos(theta)], axis=1)
            else:           # dip: circle centre above the shape
                rho = radius + v
                pts = np.stack([rho * np.sin(theta), -radius + rho * np.cos(theta)], axis=1)
        pts = (pts @ rot.T) * local_to_canvas + np.array([cx, cy])
        simplified = cv2.approxPolyDP(pts.astype(np.float32).reshape(-1, 1, 2), eps, True)
        if len(simplified) >= 2:
            placed.append(simplified)
    return placed


def layout_from(data):
    """Layout fields from a request (JSON body or multipart form)."""
    def num(key, default):
        v = data.get(key)
        return default if v in (None, "") else float(v)
    cx, cy = data.get("center_x"), data.get("center_y")
    center = None if cx in (None, "") or cy in (None, "") else (float(cx), float(cy))
    return {"center": center, "curve": num("curve", 0.0),
            "rotation": num("rotation", 0.0), "scale": num("scale", 1.0)}


def text_to_contours(text, font_name=None, font_size=80, layout=None):
    """
    Text → letter outlines in canvas pixels, placed per `layout`
    (centre, curve, rotation — see place_contours).

    Text is clean vector art, so it skips the photo filters (blur/sharpen),
    which break thin script hairlines into dots. It's rendered at 3x on its
    own canvas and traced, then placed; outlines are simplified to within
    SIMPLIFY_MM, so cursive stays connected and draws with few moves.
    """
    layout = layout or {}
    w, h = canvas_size()
    ss = TEXT_SUPERSAMPLE
    font = load_font(font_name, int(font_size * ss))

    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    _, top, _, bottom = probe.textbbox((0, 0), text, font=font, anchor="ls")
    length = font.getlength(text)
    reach = math.hypot(length / 2, bottom - top) + font.size
    reach = min(reach, 2 * math.hypot(w, h) * ss)
    side = int(2 * reach) + 2
    img = Image.new("L", (side, side), 255)
    lc = side / 2
    # Centre on the text's vertical middle (from the font's own metrics).
    ImageDraw.Draw(img).text((lc, lc - (top + bottom) / 2), text, fill=0, font=font, anchor="ms")

    # Letters become the white shapes, so every contour is a real letter
    # outline (outer edge or the inside of a hole) — no image frame to skip.
    _, binary = cv2.threshold(np.array(img), 128, 255, cv2.THRESH_BINARY_INV)
    contours, _ = cv2.findContours(binary, cv2.RETR_TREE, cv2.CHAIN_APPROX_NONE)
    return place_contours(contours, origin=(lc, lc), local_to_canvas=1 / ss,
                          width_local=length, layout=layout), (w, h)


MIN_STROKE_MM = 3.0   # shorter pieces are specks/noise: a pen dab, not a line


def stroke_length(stroke):
    return sum(math.dist(a, b) for a, b in zip(stroke, stroke[1:]))


def contours_to_strokes(contours, canvas_size):
    """
    Contours (canvas pixels) → strokes in arm mm, clipped to the sand pit.
    Pieces shorter than MIN_STROKE_MM are dropped (they draw as dots).
    """
    strokes = []
    for i in range(len(contours)):
        pts = [px_to_mm(px, py, canvas_size) for px, py in (c[0] for c in contours[i])]
        if len(pts) < 2:
            continue
        pts.append(pts[0])  # close the contour
        strokes.extend(st for st in boundary.clip_stroke(pts) if stroke_length(st) >= MIN_STROKE_MM)
    return strokes


def order_strokes(strokes, start):
    """
    Nearest-next drawing order: after each stroke, go to the closest
    remaining one. Open strokes may be drawn backwards; closed loops start
    at their point nearest the pen. Cuts pen-up travel dramatically compared
    to the order the tracer finds shapes in.
    """
    if len(strokes) < 2:
        return list(strokes)
    closed = [math.dist(st[0], st[-1]) < 0.5 for st in strokes]
    pts, owner, vertex = [], [], []
    for i, st in enumerate(strokes):
        # Loops: ~24 candidate entry points; open strokes: either end.
        verts = range(0, len(st) - 1, max(1, (len(st) - 1) // 24)) if closed[i] else (0, len(st) - 1)
        for v in verts:
            pts.append(st[v]); owner.append(i); vertex.append(v)
    P, owner, vertex = np.array(pts, float), np.array(owner), np.array(vertex)
    alive = np.ones(len(P), bool)
    pos = np.array(start, float)
    ordered = []
    for _ in range(len(strokes)):
        d = np.where(alive, ((P - pos) ** 2).sum(axis=1), np.inf)
        k = int(np.argmin(d))
        i, v = int(owner[k]), int(vertex[k])
        st = strokes[i]
        if closed[i]:
            loop = st[:-1]
            st = loop[v:] + loop[:v] + [loop[v]]
        elif v != 0:
            st = st[::-1]
        ordered.append(st)
        pos = np.array(st[-1], float)
        alive[owner == i] = False
    return ordered


# Seconds per G-code move, measured on the arm (text jobs ≈ 0.2 s/move).
SECONDS_PER_MOVE = 0.25
MAX_DRAW_MINUTES = 90  # refuse drawings that would take longer than this


def estimate_minutes(moves):
    return round(moves * SECONDS_PER_MOVE / 60, 1)


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
    for stroke in order_strokes(strokes, last):
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


def strokes_json(strokes, contours, size):
    """
    Preview data for the app, which draws it itself so it can drag/rotate
    instantly: "strokes" = what will be drawn (clipped, arm mm); "full" =
    the whole unclipped outline, shown faintly so clipped parts are visible.
    """
    full = [[list(px_to_mm(float(x), float(y), size)) for x, y in (pt[0] for pt in c)] for c in contours]
    try:
        moves = len(strokes_to_gcode(strokes, 5))
    except ValueError:
        moves = None
    return {"strokes": [[list(p) for p in st] for st in strokes], "full": full,
            "stroke_count": len(strokes), "moves": moves,
            "minutes": estimate_minutes(moves) if moves else None,
            "max_minutes": MAX_DRAW_MINUTES}


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
        faint = [np.round(c).astype(np.int32) for c in contours]
        cv2.drawContours(img, faint, -1, (200, 200, 200), 1)  # full image, faint
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
    if not freenove.connected:
        state = "offline"
    elif robot_busy.locked():
        state = "drawing"
    else:
        state = "idle"
    return jsonify({
        "state": state,
        "connected": freenove.connected,
        "queue_length": 1 if robot_busy.locked() else 0,
        "job_id": current_job["id"],
    })


@app.route("/connect", methods=["POST"])
@idempotent
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
@idempotent
@refuse_while_busy
def load_motors():
    """Enable motors."""
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    freenove.enable_motors()
    return jsonify({"success": True})


@app.route("/relax", methods=["POST"])
@idempotent
@refuse_while_busy
def relax_motors():
    """Disable/relax motors."""
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    freenove.disable_motors()
    return jsonify({"success": True})


@app.route("/stop", methods=["POST"])
@idempotent
def stop_arm():
    """
    Graceful stop: stop sending moves, let the few already queued on the arm
    finish, then lift, tuck up and unload (the running job does this when it
    sees `abort`). If nothing is drawing, just rest the arm.
    """
    if not freenove.connected:
        return jsonify({"success": False, "message": "Not connected"}), 400
    if robot_busy.locked():
        freenove.abort = True
        return jsonify({"success": True, "stopping": True, "job_id": current_job["id"]})

    def _rest():
        with robot_busy:
            freenove.rest()
            status_idle()
    threading.Thread(target=_rest, daemon=True).start()
    return jsonify({"success": True, "stopping": False})


@app.route("/emergency-stop", methods=["POST"])
@idempotent
def emergency_stop():
    """
    Last resort: Freenove's S13 cuts motor power instantly (the arm drops)
    and exits the arm server; systemd restarts it and this bridge.
    """
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
        contours, canvas_size = image_to_contours(
            image_bytes, threshold, gauss, sharpen, layout_from(request.form)
        )
        strokes = contours_to_strokes(contours, canvas_size)
        if request.form.get("format") == "json":
            return jsonify(strokes_json(strokes, contours, canvas_size))
        preview = render_pit_preview(strokes, contours, canvas_size)
        return send_file(io.BytesIO(preview), mimetype="image/png")
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/auto-settings", methods=["POST"])
def auto_settings():
    """Best threshold/blur/sharpen for an uploaded picture (multipart 'image')."""
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400
    try:
        return jsonify(auto_image_settings(request.files["image"].read()))
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/draw", methods=["POST"])
@idempotent(persist=True)
def draw():
    """
    Process an image or text and send drawing commands to the arm.

    For images: multipart form with 'image' file + optional params
    For text: JSON body with 'text', optional 'font_name', 'font_size'

    Both go through the same contour → G-code pipeline.

    With an X-Request-ID (current app) the reply comes as soon as the request
    has arrived (202); the app then follows /job/<id>: "processing" while the
    moves are worked out, "rejected" (with the reason) if it can't be drawn,
    else "drawing". Without one (older builds) the reply comes after
    processing, with any rejection as a 400, like before.
    """
    if not freenove.connected:
        return jsonify({"error": "Not connected to arm"}), 400

    try:
        spec = read_draw_request()
        quick_ack = bool(request.headers.get("X-Request-ID"))
        gcode = None if quick_ack else plan_drawing(spec)

        # One drawing at a time
        job_id = start_job(spec, gcode)
        if job_id is None:
            return jsonify({
                "error": f"Robot is busy drawing \"{current_job['label']}\" — wait for it to finish.",
                "busy": True,
                "job_id": current_job["id"],
            }), 409
        if quick_ack:
            return jsonify({"accepted": True, "job_id": job_id, "status": "processing"}), 202
        return jsonify({
            "accepted": True,
            "job_id": job_id,
            "gcode_count": len(gcode),
        })

    except Rejected as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


class Rejected(Exception):
    """A drawing the bridge won't do: bad request, nothing in the pit, too long, off limits."""


def read_draw_request():
    """The /draw request's settings and picture or text (no processing yet)."""
    if request.content_type and "multipart" in request.content_type:
        # Image upload
        if "image" not in request.files:
            raise Rejected("No image provided")
        return {
            "source": "image",
            "label": request.form.get("label", "Image Drawing"),
            "image_bytes": request.files["image"].read(),
            "threshold": int(request.form.get("threshold", DEFAULT_THRESHOLD)),
            "gauss": int(request.form.get("gauss", DEFAULT_GAUSS)),
            "sharpen": int(request.form.get("sharpen", DEFAULT_SHARPEN)),
            "pen_up_height": int(request.form.get("pen_up_height", DEFAULT_PEN_UP_HEIGHT)),
            "layout": layout_from(request.form),
        }
    if request.is_json:
        # Text input
        data = request.get_json()
        text = data.get("text", "")
        if not text:
            raise Rejected("No text provided")
        return {
            "source": "text",
            "label": text,
            "text": text,
            "font_name": data.get("font_name", None),
            "font_size": data.get("font_size", 80),
            "pen_up_height": data.get("pen_up_height", DEFAULT_PEN_UP_HEIGHT),
            "layout": layout_from(data),
        }
    raise Rejected("Invalid content type")


def plan_drawing(spec):
    """Picture or text → G-code checked against the pit. Raises Rejected if it can't be drawn."""
    if spec["source"] == "image":
        contours, size = image_to_contours(
            spec["image_bytes"], spec["threshold"], spec["gauss"], spec["sharpen"], spec["layout"]
        )
    else:
        contours, size = text_to_contours(spec["text"], spec["font_name"], spec["font_size"],
                                          spec["layout"])

    # Convert contours → clipped strokes → G-code
    strokes = contours_to_strokes(contours, size)
    if not strokes:
        raise Rejected("Nothing to draw inside the pit — try adjusting threshold")
    gcode = strokes_to_gcode(strokes, spec["pen_up_height"])
    minutes = estimate_minutes(len(gcode))
    if minutes > MAX_DRAW_MINUTES:
        raise Rejected(f"Too detailed: {len(strokes)} strokes, about {minutes:.0f} min to draw "
                       f"(limit {MAX_DRAW_MINUTES}). Try a lower threshold, more blur, "
                       f"or a simpler picture.")

    reason = preflight(gcode)
    if reason:
        raise Rejected(f"Blocked by pit boundary: {reason}")
    return gcode


def start_job(spec, gcode=None):
    """
    Reserve the robot and run the job in a background thread; returns the
    job id, or None if the robot is busy. Without G-code the job works it
    out first, holding the robot so nothing else can start meanwhile.
    """
    if not robot_busy.acquire(blocking=False):
        return None
    job_id = str(uuid.uuid4())[:8]
    current_job.update(id=job_id, label=spec["label"])
    freenove.abort = False  # a Stop from now on ends this job, even before the arm moves

    # Track the job
    with jobs_lock:
        jobs[job_id] = {
            "status": "processing" if gcode is None else "queued",
            "created_at": datetime.now().isoformat(),
            "label": spec["label"],
            "source": spec["source"],
            "gcode_count": 0 if gcode is None else len(gcode),
        }

    try:
        if gcode is not None:
            status_receiving()
        threading.Thread(target=execute_job, args=(job_id, spec, gcode), daemon=True).start()
    except Exception:
        current_job.update(id=None, label=None)
        robot_busy.release()  # never leave the robot stuck "busy"
        raise
    return job_id


def execute_job(job_id, spec, gcode):
    try:
        if gcode is None:
            try:
                gcode = plan_drawing(spec)
            except Exception as e:
                if not isinstance(e, Rejected):
                    traceback.print_exc()
                print(f"[Bridge] Job {job_id} rejected: {e}")
                with jobs_lock:
                    jobs[job_id].update(status="rejected", error=str(e))
                return
            with jobs_lock:
                jobs[job_id]["gcode_count"] = len(gcode)
            if freenove.abort:  # stopped before the arm moved
                with jobs_lock:
                    jobs[job_id].update(status="failed", error="Stopped")
                return
            status_receiving()
        run_job(job_id, gcode)
    except Exception:
        traceback.print_exc()
        with jobs_lock:
            jobs[job_id]["status"] = "failed"
            jobs[job_id]["error"] = "Bridge error during drawing — check the log"
        status_error()
    finally:
        current_job.update(id=None, label=None)
        robot_busy.release()


def run_job(job_id, gcode):
    with jobs_lock:
        jobs[job_id]["status"] = "drawing"
    status_drawing()
    freenove.homed = False  # re-home every job to correct drift
    freenove.ensure_ready()

    success = freenove.send_gcode_batch(gcode)
    stopped = freenove.abort
    if stopped:
        success = False

    # Photograph the result from the camera view, then tuck up and unload.
    # A stopped job skips the photo and goes straight to resting.
    photo = None
    if not stopped:
        park_at_view()
        photo = take_photo(job_id) if success else None
    freenove.rest()

    with jobs_lock:
        jobs[job_id]["photo"] = bool(photo)
        jobs[job_id]["status"] = "completed" if success else "failed"
        if stopped:
            jobs[job_id]["error"] = "Stopped"
        elif freenove.violation:
            jobs[job_id]["error"] = f"Blocked by pit boundary: {freenove.violation}"
    if success:
        status_complete()
        def _to_idle():
            time.sleep(5)
            status_idle()
        threading.Thread(target=_to_idle, daemon=True).start()
    elif stopped:
        status_idle()  # a deliberate stop isn't an error
    else:
        status_error()


def park_at_view():
    """Lift straight up where the pen is, then go to the camera view position."""
    print("[Bridge] Moving to camera view position...")
    if freenove.pos is not None:
        x, y, _ = freenove.pos
        if reachable(x, y, boundary.safe_z):
            freenove.move_to(x, y, boundary.safe_z, trusted=True)  # clear the rim
            time.sleep(2)
    vx, vy, vz = view_position()
    freenove.move_to(vx, vy, vz, trusted=True)
    time.sleep(4)


def fold_and_relax():
    """End of session: tuck the arm up and turn the motors off."""
    if freenove.connected:
        freenove.rest()
    status_idle()


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
@idempotent
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
    """
    Get the status of a drawing job: processing → drawing → completed or
    failed, or processing → rejected (with the reason in "error").
    """
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
@idempotent
@refuse_while_busy
def move():
    """Move the arm to a specific position."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    data = request.get_json()
    position = data.get("position", "home")
    freenove.ensure_ready()
    if position == "home":
        freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], HOME_POSITION[2])
    elif position == "overview":
        freenove.move_to(HOME_POSITION[0], HOME_POSITION[1],
                         HOME_POSITION[2] + DEFAULT_PEN_UP_HEIGHT)
    elif position == "view":
        threading.Thread(target=park_at_view, daemon=True).start()
    elif position == "fold":
        threading.Thread(target=fold_and_relax, daemon=True).start()
    return jsonify({"accepted": True})


@app.route("/home", methods=["POST"])
@idempotent
@refuse_while_busy
def go_home():
    """Send arm to home position."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], HOME_POSITION[2])
    return jsonify({"success": True})

@app.route("/z-height", methods=["GET"])
def get_z_height():
    return jsonify({"z_height": HOME_POSITION[2]})


@app.route("/set-z", methods=["POST"])
@idempotent
@refuse_while_busy
def set_z_height():
    """Set the pen-down height, move the pen there at home, and save it."""
    data = request.get_json() or {}
    new_z = round(float(data.get("z_height", HOME_POSITION[2])), 1)
    reason = boundary.check_move(None, (HOME_POSITION[0], HOME_POSITION[1], new_z))
    if reason:
        return jsonify({"success": False, "error": reason, "z_height": HOME_POSITION[2]}), 400
    HOME_POSITION[2] = new_z
    boundary.surface_z = new_z
    cfg = load_robot_config()
    cfg["draw_z"] = new_z
    save_robot_config(cfg)
    if freenove.connected:
        status_calibrating()
        freenove.ensure_ready()
        freenove.move_to(HOME_POSITION[0], HOME_POSITION[1], new_z)
    print(f"[Bridge] Z height updated to {new_z}mm")
    return jsonify({"success": True, "z_height": new_z})

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
@idempotent
@refuse_while_busy
def set_boundary():
    """Replace the outline: {"polygon": [[x, y], ...], "smooth": bool}."""
    data = request.get_json() or {}
    try:
        boundary.set_polygon(data["polygon"], smooth=bool(data.get("smooth", False)))
    except (KeyError, ValueError, TypeError) as e:
        return jsonify({"error": str(e)}), 400
    return get_boundary()


@app.route("/boundary/settings", methods=["POST"])
@idempotent
@refuse_while_busy
def set_boundary_settings():
    """{"rim_clearance_mm", "margin_mm", "safe_z"} — any may be omitted."""
    data = request.get_json() or {}
    boundary.update_settings(data.get("safe_z"), data.get("margin_mm"), data.get("rim_clearance_mm"))
    return get_boundary()


@app.route("/boundary/reset", methods=["POST"])
@idempotent
@refuse_while_busy
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
        contours, size = text_to_contours(text, data.get("font_name"), data.get("font_size", 80),
                                          layout_from(data))
        strokes = contours_to_strokes(contours, size)
        if data.get("format") == "json":
            return jsonify(strokes_json(strokes, contours, size))
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
@idempotent
@refuse_while_busy
def calibrate_start():
    """Home the arm and park the pen just above the sand at the home point."""
    if not freenove.connected:
        return jsonify({"error": "Not connected"}), 400
    status_calibrating()
    freenove.ensure_ready()
    freenove.move_to(HOME_POSITION[0], HOME_POSITION[1],
                     HOME_POSITION[2] + DEFAULT_PEN_UP_HEIGHT, trusted=True)
    calibration_points.clear()
    return get_position()


@app.route("/calibrate/jog", methods=["POST"])
@idempotent
@refuse_while_busy
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
@idempotent
def calibrate_record():
    """Record the pen's current XY as the next rim point."""
    if freenove.pos is None:
        return jsonify({"error": "Position unknown"}), 400
    calibration_points.append([freenove.pos[0], freenove.pos[1]])
    return get_position()


@app.route("/calibrate/undo", methods=["POST"])
@idempotent
def calibrate_undo():
    if calibration_points:
        calibration_points.pop()
    return get_position()


@app.route("/calibrate/save", methods=["POST"])
@idempotent
def calibrate_save():
    """Save recorded rim points as the new (smoothed) boundary."""
    if len(calibration_points) < 5:
        return jsonify({"error": "Record at least 5 rim points first"}), 400
    boundary.set_polygon(list(calibration_points), smooth=True)
    return get_boundary()


@app.route("/calibrate/finish", methods=["POST"])
@idempotent
@refuse_while_busy
def calibrate_finish():
    """Lift clear of the rim, tuck the arm up and unload the motors."""
    if freenove.connected and freenove.pos is not None:
        x, y, _ = freenove.pos
        if reachable(x, y, boundary.safe_z):
            freenove.move_to(x, y, boundary.safe_z, trusted=True)
            time.sleep(2)
        freenove.rest()
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
