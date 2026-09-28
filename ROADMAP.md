# SandBot Roadmap

Goal: plug the robot in once (at Laila's apartment) and never think about it
again. It sits idle drawing almost no power, wakes up when a drawing is sent
from the app, draws safely inside the pit, photographs the result for History,
and goes back to sleep.

## Now: safe, unattended job cycle

- [ ] **Home only with the pen lifted.** Freenove's homing (`S10`) starts with
      a blind 400/270-step kick of motors 2 and 3 from wherever the arm is.
      From a low pose that drives the pen through the paper / into the sand
      and pit floor. The bridge must always lift above the safe Z first, then home.
- [ ] **End-of-job sequence:** finish drawing → lift over the rim → re-home up
      high → camera view position → photo for History → fold → **unload the
      motors** (no holding current, safe to leave on 24/7).
- [ ] **Start-of-job sequence from the folded, unloaded state:** enable motors →
      lift out of the fold → home up high → draw.
- [ ] Remove the old post-drawing re-home that happens right above the surface.
- [ ] Fold / Relax buttons in the app (manual end-of-session).
- [ ] Power-on safety: after a reboot or power cut the arm must not move
      until a job is sent (it currently doesn't — keep it that way).

## Drawing quality

- [x] Text pipeline for text: 3x render, no photo filters, outlines simplified
      to 0.3 mm (script fonts no longer break into dots; ~5x fewer moves).
- [x] Fast boundary checks (precomputed pit map): drawings prepare in ~0.4 s.
- [x] Graceful Stop Drawing button (finish queued moves → lift → tuck → unload).
- [ ] Try a fine pen and re-calibrate pen height for crisper lines.

- [ ] Draw strokes in nearest-next order instead of OpenCV's jumpy order
      (same strokes, less travel, less jumping around).
- [x] Keep both outlines (outer + inner) for text for now — looks nicer in
      tests. Revisit a single-line option if it gets messy in sand.
- [ ] Accuracy test pattern (square, cross, circles at known sizes) to measure
      arm error with a ruler.

## Text editor preview

- [ ] Much larger text size range (pit fits letters > 10 cm tall).
- [ ] Drag the text anywhere in the pit on the preview (instant on-device,
      exact server render on release).
- [ ] Curve slider: bend text along an arc to follow the kidney's top edge or
      wrap around the notch.

## Base LEDs (smart plug)

The base LEDs are a dumb strip, so control their power with a smart plug that
has a **local** API (no cloud): e.g. TP-Link Kasa (python-kasa) or Shelly Plug
(plain HTTP).

- [ ] Bridge turns the plug on when a job arrives.
- [ ] Turns it off 5 minutes after the job finishes.
- [ ] Consider LEDs off (or white) during the completion photo — the red strip
      washes out the camera.

## Camera

- [ ] 3D-printed mount so the camera points straight down (and swaps easily
      with the pencil holder).
- [ ] Re-save the camera view position after mounting (Settings → Sand Pit →
      Save as Camera View).

## Patterns without Claude

- [ ] Pattern tab sends vector strokes straight to the robot (`/draw-strokes`)
      instead of image contours.
- [ ] Replace Claude-generated patterns with built-in generators; add new
      patterns to the app as code updates instead of API calls.

## Security

- [x] Remove the Anthropic API key and GitHub token from the app binary
      (`config.swift` and `ClaudeService.swift` deleted, keys revoked 2026-09-27).
- [x] Block a second drawing while one is running (409 "busy"; arm-moving
      endpoints refuse mid-job).
- [ ] Shared access token between app and bridge (Tailscale already limits
      the network to your own devices; this is defence in depth).

## Moving it to the apartment

- [ ] Add her Wi-Fi to the Pi before the move (`nmcli`), confirm Tailscale
      reconnects on its own after a reboot.
- [ ] Power-cut resilience: everything starts from systemd on boot (arm,
      bridge, camera already do).
- [ ] Let the bridge be restarted without typing a sudo password (narrow
      sudoers rule for `systemctl restart sandbot-*`), for easier updates.
