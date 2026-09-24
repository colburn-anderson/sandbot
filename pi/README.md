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
| `robot_config.json` | Camera view / rest position the arm parks at after a drawing |
| `camera_stream.py` | MJPEG stream + `/snapshot.jpg` |
| `systemd/*.service` | Units for `sandbot-arm`, `sandbot-bridge`, `sandbot-camera` |

The Freenove arm server (`~/Freenove_Robot_Arm_Kit_for_Raspberry_Pi/Server/Code`)
is the vendor kit and isn't copied here.

## Deploy

From the repo root on the Mac:

```bash
scp pi/*.py pi/*.json tallergiraffe@100.95.15.84:~/sandbot/
```

Then on the Pi:

```bash
sudo systemctl restart sandbot-bridge sandbot-camera
```

## Useful endpoints

- `GET /boundary`, `POST /boundary/settings {"safe_z", "margin_mm"}`
- `GET /position`, `POST /calibrate/start|jog|record|undo|save|finish`
- `GET|POST /view-position` (POST saves the pen's current position)
- `GET /job/<id>`, `GET /job/<id>/photo`
