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
| Userspace | `obs-backgroundremoval` | AUR | The ML segmentation plugin for OBS — runs ONNX models. **On Linux this runs CPU-only** (see note below) |
| Userspace (optional) | `openvino` | AUR | Intel's AI inference toolkit. Note: installing it does **not** add an NPU device to the OBS plugin on Linux |

The virtual cam config (`devices=1 video_nr=10 card_label='AI Camera'
exclusive_caps=1`) is set persistently via `/etc/modprobe.d/` so the
device is reproducible across reboots.

> ### Reality check: no NPU through obs-backgroundremoval on Linux
>
> The original version of this module claimed you could pick an
> *Inference Device → NPU* in the obs-backgroundremoval filter once the AUR
> `openvino` package was installed. **That is not correct on Linux.**
>
> obs-backgroundremoval's selectable inference providers on Linux are
> **CUDA / ROCm / MIGraphX** (and ROCm was dropped in ONNX Runtime 1.23).
> There is **no OpenVINO / NPU execution provider** in its Linux builds, so
> installing AUR `openvino` does **not** add an NPU device to the OBS
> filter — the path is effectively **CPU-only**. The OBS + v4l2loopback
> pipeline below still gives you working background blur; it is just CPU,
> not NPU-accelerated. (Also note obs-backgroundremoval issue
> [#759](https://github.com/occ-ai/obs-backgroundremoval/issues/759) (open):
> non-CPU inference processes only one frame then stops.)
>
> **Want the NPU?** Use a purpose-built tool instead:
> [`ericjchang/linux-studio-effects`](https://github.com/ericjchang/linux-studio-effects)
> — OpenVINO + v4l2loopback, with blur / auto-framing / portrait-lighting
> that actually target the NPU. Honest caveats: it is **validated on Arrow
> Lake (Core Ultra 9 285H), not yet on Panther Lake**, and installs via
> `git clone` + `pip` + a separate NPU driver — there is **no distro
> package**. Treat it as the real NPU route, this OBS path as the
> CPU-blur fallback.

## Install

```sh
./patch.sh install webcam-ai-fix
```

This installs the kernel module + OBS + background removal plugin
(~5 min). Inference runs on **CPU**, which is enough for 720p / 30 fps
background blur.

OpenVINO (`paru -S openvino`, AUR-only, ~30 min compile) is **not**
needed for this path and does **not** unlock NPU acceleration inside the
OBS plugin on Linux — there is no OpenVINO/NPU execution provider in
obs-backgroundremoval's Linux builds, and no *Inference Device → NPU*
dropdown appears. For an actual NPU pipeline see
[`ericjchang/linux-studio-effects`](https://github.com/ericjchang/linux-studio-effects)
(see the reality-check note above).

## Use

1. Open **OBS Studio**.
2. Sources panel → `+` → **Video Capture Device** → pick `/dev/video2`
   (or whichever node your USB UVC webcam shows up as).
3. Right-click the source → **Filters** → `+` → **Background Removal**.
   Configure blur amount and model. Inference runs on CPU (the Linux
   build has no NPU option, regardless of whether `openvino` is
   installed).
4. **Tools → Start Virtual Camera**. Default writes to `/dev/video10`.
5. In your video-chat app (Zoom, Discord, Chrome Meet, browser, Teams),
   pick **"AI Camera"** as the camera.

That's it.

## Verify

```sh
./patch.sh status webcam-ai-fix
```

Reports NPU device permissions, v4l2loopback load state, virtual cam
presence, OBS + plugin install state, and whether OpenVINO (if installed)
can see the NPU at runtime. Note the OpenVINO/NPU readout is informational
only — obs-backgroundremoval cannot use it (CPU-only on Linux); it matters
for the `linux-studio-effects` route or a standalone OpenVINO script.

## v4l2loopback coexistence (read if you use another virtual-cam tool)

This module ships a **global** `options v4l2loopback ... video_nr=10`
line in `/etc/modprobe.d/`. If another tool on the machine already drives
v4l2loopback, the two configs collide: modprobe **concatenates** all
`options` lines for a module, and `devices=1` means only **one** node
spawns — so whichever loads first wins and the other tool's node never
appears.

On the reference machine this is a live conflict: `linuxdrop` already
uses v4l2loopback on `video_nr=20` ("LinuxDrop Camera"). Don't ship two
competing global `options` lines. Instead use a **single shared
multi-device** config, e.g.:

```sh
# /etc/modprobe.d/v4l2loopback-options.conf  (one line, shared)
options v4l2loopback devices=2 video_nr=10,20 \
  card_label="AI Camera","LinuxDrop Camera" exclusive_caps=1,1
```

Then neither tool should drop its own `options v4l2loopback` line. If you
can't merge them, coordinate `video_nr` and total `devices=` count by
hand. (`exclusive_caps=1` is per-device; list one value per node.)

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

This is one of the two real NPU routes (the other being
`ericjchang/linux-studio-effects`). Unlike the OBS plugin, a standalone
OpenVINO script *can* compile a model to the `NPU` device directly. For
maximum NPU utilisation with a tiny script:

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
