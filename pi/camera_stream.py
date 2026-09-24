#!/usr/bin/env python3
"""
camera_stream.py — MJPEG stream from the Arducam IMX708 for the SandBot app.

  GET /video          multipart MJPEG stream (what the app's Live Feed shows)
  GET /snapshot.jpg   latest single frame
  GET /               tiny browser page for testing

One background thread captures and encodes frames; every viewer shares the
latest one, so extra viewers don't cost extra camera work. Frame rate and
size are kept modest so it streams smoothly to a phone over Tailscale.
"""

import threading
import time

import cv2
from flask import Flask, Response
from libcamera import controls
from picamera2 import Picamera2

PORT = 8000
SIZE = (1280, 720)
FPS = 12
JPEG_QUALITY = 70

app = Flask(__name__)

camera = Picamera2()
# 2304x1296 is the IMX708's 2x2-binned full-sensor mode. Without asking for
# it, libcamera picks 1536x864, which is a centre crop (narrower view).
SENSOR_MODE = (2304, 1296)

camera.configure(camera.create_video_configuration(
    main={"size": SIZE, "format": "RGB888"},
    raw={"size": SENSOR_MODE},
    controls={"FrameRate": FPS},
))
camera.start()
try:
    # IMX708 has autofocus; keep refocusing as the arm moves.
    camera.set_controls({"AfMode": controls.AfModeEnum.Continuous,
                         "AfSpeed": controls.AfSpeedEnum.Fast})
except Exception as e:
    print(f"[Camera] Autofocus not available: {e}")

latest_jpeg = None
frame_ready = threading.Condition()


def capture_loop():
    global latest_jpeg
    while True:
        frame = camera.capture_array()
        ok, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        if ok:
            with frame_ready:
                latest_jpeg = jpeg.tobytes()
                frame_ready.notify_all()


def generate():
    while True:
        with frame_ready:
            frame_ready.wait(timeout=2)
            jpeg = latest_jpeg
        if jpeg is None:
            continue
        yield (b"--frame\r\n"
               b"Content-Type: image/jpeg\r\n"
               b"Content-Length: " + str(len(jpeg)).encode() + b"\r\n\r\n" +
               jpeg + b"\r\n")


@app.route("/")
def index():
    return '<html><body style="margin:0;background:#000"><img src="/video" style="width:100%"></body></html>'


@app.route("/video")
def video():
    return Response(generate(), mimetype="multipart/x-mixed-replace; boundary=frame")


@app.route("/snapshot.jpg")
def snapshot():
    deadline = time.time() + 3
    while latest_jpeg is None and time.time() < deadline:
        time.sleep(0.05)
    if latest_jpeg is None:
        return "No frame yet", 503
    return Response(latest_jpeg, mimetype="image/jpeg")


if __name__ == "__main__":
    threading.Thread(target=capture_loop, daemon=True).start()
    print(f"[Camera] Streaming {SIZE[0]}x{SIZE[1]} @ {FPS} fps on :{PORT}")
    app.run(host="0.0.0.0", port=PORT, threaded=True)
