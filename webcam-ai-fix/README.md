# webcam-ai-fix

The Linux equivalent of **Windows Studio Effects** for the Intel Panther
Lake NPU on this laptop. Lets you run AI camera effects (background blur /
replace, smart framing, voice focus) on real-time video and pipe the
result to any video-chat app.

## What this module sets up

| Layer | Component | Source | Purpose |
|---|---|---|---|
| Kernel | `intel_vpu` driver | mainline (already loaded) | Talks to NPU hardware |
| Kernel | `v4l2loopback-dkms` | `extra` | Creates `/dev/video10` "AI Camera" — the virtual webcam apps will read from |
| Userspace | `obs-studio` | `extra` | Captures real cam, applies filter graph, writes to virtual cam |
| Userspace | `obs-backgroundremoval` | AUR | The ML segmentation plugin for OBS — runs ONNX models, can target NPU via OpenVINO |
| Userspace (optional) | `openvino` | AUR | Intel's official AI inference toolkit, lets the plugin actually use the NPU rather than CPU |

The virtual cam config (`devices=1 video_nr=10 card_label='AI Camera'
exclusive_caps=1`) is set persistently via `/etc/modprobe.d/` so the
device is reproducible across reboots.

## Install

```sh
./patch.sh install webcam-ai-fix
```

Default install is the **fast path** (~5 min): kernel module + OBS +
background removal plugin. Inference runs on CPU/TFLite by default, which
is enough for 720p / 30 fps background blur.

For NPU acceleration, install OpenVINO separately (optional, ~30 min
compile from AUR):

```sh
paru -S openvino
```

After OpenVINO is on the system, the obs-backgroundremoval filter exposes
an *Inference Device* dropdown — pick `NPU`.

## Use

1. Open **OBS Studio**.
2. Sources panel → `+` → **Video Capture Device** → pick `/dev/video2`
   (or whichever node your USB UVC webcam shows up as).
3. Right-click the source → **Filters** → `+` → **Background Removal**.
   Configure blur amount, model, and (if `openvino` is installed)
   inference device = `NPU`.
4. **Tools → Start Virtual Camera**. Default writes to `/dev/video10`.
5. In your video-chat app (Zoom, Discord, Chrome Meet, browser, Teams),
   pick **"AI Camera"** as the camera.

That's it.

## Verify

```sh
./patch.sh status webcam-ai-fix
```

Reports NPU device permissions, v4l2loopback load state, virtual cam
presence, OBS + plugin install state, and whether OpenVINO can see the
NPU at runtime.

## Without OBS

If the OBS pipeline feels heavy, two lighter alternatives:

### `backscrub` — daemon style

```sh
paru -S backscrub-git
backscrub -v /dev/video2 -V /dev/video10 -m mediapipe.tflite
```

Runs on CPU via TensorFlow Lite. ~25-50 ms per frame on this CPU.
Daemonise with a small systemd user unit.

### Standalone Python + OpenVINO + NPU

For maximum NPU utilisation with a tiny script:

```python
import cv2, openvino as ov, numpy as np
core = ov.Core()                                                 # auto-detects NPU
model = core.compile_model("background-segmentation.xml", "NPU") # explicit NPU device
cap = cv2.VideoCapture('/dev/video2')
out = open('/dev/video10', 'wb')
while True:
    ok, frame = cap.read()
    if not ok: break
    mask = model([frame])[0]
    blurred = cv2.GaussianBlur(frame, (45, 45), 0)
    composed = np.where(mask > 0.5, frame, blurred)
    out.write(composed.tobytes())
```

Use OpenVINO's [Open Model Zoo](https://github.com/openvinotoolkit/open_model_zoo)
for ready segmentation models, or convert any ONNX model via
`ovc <model>.onnx`.

## What you can't easily get on Linux

Windows Studio Effects bundles **Eye Contact Correction** (gaze redirection
to camera) — there's no polished Linux equivalent. The closest open-source
project is `dtoyoda10/eye-contact-cnn`, but it's research-grade, CPU-only,
and not packaged for any distro. If the feature matters, expect to build
from source and live with limitations.

## Uninstall

```sh
./patch.sh uninstall webcam-ai-fix
```

Unloads `v4l2loopback` and removes the modules-load + modprobe-options
files. Packages (obs, plugin, openvino if installed) are left so the
revert is reversible without re-fetching from the network. Remove fully
with `sudo pacman -Rns v4l2loopback-dkms obs-studio` and
`paru -Rns obs-backgroundremoval openvino`.
