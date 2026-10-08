# SandBot — Raspberry Pi side

Copies of what runs on the Pi (`tallergiraffe@100.95.15.84`, Tailscale) in
`~/sandbot/`. The Pi is the source of truth while hacking; copy changes back
here to commit them.

```
[iOS app] --HTTP :8080--> sandbot_bridge.py --TCP :5000--> Freenove main.py --> arm
[iOS app] --MJPEG :8000--> camera_stream.py (Arducam IMX708)
```

| File | What it is |
|---|---|
| `sandbot_bridge.py` | Flask bridge the app talks to: image/text → contours → G-code, jobs, calibration, photos |
| `boundary.py` | Sand pit outline + safety checks. Every move below the safe Z must stay inside the pit |
| `boundary.json` | The calibrated pit outline (traced rim, smoothed), safe Z and margin |
| `robot_config.json` | Pen-down height (`draw_z`) and the camera view position the arm parks at after a drawing |
| `camera_stream.py` | MJPEG stream + `/snapshot.jpg` |
| `systemd/*.service` | Units for `sandbot-arm`, `sandbot-bridge`, `sandbot-camera` |

The Freenove arm server (`~/Freenove_Robot_Arm_Kit_for_Raspberry_Pi/Server/Code`)
is the vendor kit and isn't copied here.

## Deploy

Copy only the code, from the repo root on the Mac. The `.json` files are live
settings the app saves on the Pi (pen height, camera view, pit outline), and
the copies here can be out of date, so never copy them over the Pi's. An old
`robot_config.json` without `draw_z` would drop the pen to the default
height, into the surface.

```bash
scp pi/*.py tallergiraffe@100.95.15.84:~/sandbot/
```

Then on the Pi (restart `sandbot-camera` too only if `camera_stream.py`
changed and the camera is in use):

```bash
sudo systemctl restart sandbot-bridge
```

To update the repo's copies of the settings, copy them back from the Pi:

```bash
scp tallergiraffe@100.95.15.84:~/sandbot/robot_config.json tallergiraffe@100.95.15.84:~/sandbot/boundary.json pi/
```

## Useful endpoints

- `POST /draw` with an `X-Request-ID` header answers `202` as soon as the
  request arrives; then follow `GET /job/<id>`: `processing` → `drawing` →
  `completed`/`failed`, or `rejected` with the reason in `error`
- Any request that changes something can carry `X-Request-ID`: a resend with
  the same ID gets the first reply instead of running again. The app resends
  whatever got no answer while the Pi's Wi-Fi was hopping between the
  router's radios. Drawing replies are kept in `recent_requests.json`.
- `GET /boundary`, `POST /boundary/settings {"safe_z", "margin_mm"}`
- `GET /position`, `POST /calibrate/start|jog|record|undo|save|finish`
- `GET|POST /view-position` (POST saves the pen's current position)
- `GET /job/<id>`, `GET /job/<id>/photo`
