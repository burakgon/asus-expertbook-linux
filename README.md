<div align="center">

# asus-expertbook-linux

**Linux compatibility patches for the 2026 ASUS ExpertBook Ultra (B9406CAA)** —
packaged as a tracked, versioned, reversible patcher.

[![GitHub Pages](https://img.shields.io/badge/site-burakgon.github.io-7dd3fc?style=flat-square)](https://burakgon.github.io/asus-expertbook-linux/)
[![License: MIT](https://img.shields.io/badge/license-MIT-c4b5fd?style=flat-square)](LICENSE)
[![Linux 6.18+](https://img.shields.io/badge/linux-6.18%2B-86efac?style=flat-square)](#kernel--distro-compatibility)
[![Hardware](https://img.shields.io/badge/hardware-B9406CAA-fbbf24?style=flat-square)](#is-this-repo-for-me)
[![No kernel patches required](https://img.shields.io/badge/kernel%20patches-not%20required-86efac?style=flat-square)](#how-it-works)

[**🌐 Documentation site**](https://burakgon.github.io/asus-expertbook-linux/) ·
[**Quick install**](#quick-install) ·
[**Modules**](#modules) ·
[**Before / after**](#what-this-actually-fixes--before--after) ·
[**FAQ**](#faq)

</div>

---

## Is this repo for me?

It's for you if **all** of the following are true. The single command below
checks them in one go:

```sh
curl -fsSL https://raw.githubusercontent.com/burakgon/asus-expertbook-linux/main/scripts/check-hardware.sh | bash
```

| Check | Expected | Why it matters |
|---|---|---|
| Laptop model (DMI) | `ASUS EXPERTBOOK B9406CAA` | All fixes are scoped to this exact subsystem ID |
| CPU family | Intel Core Ultra Series 3 (Panther Lake) | Required for the `xe` driver / `iwlmld` paths |
| Touchpad | PixArt I²C-HID `093A:4F05` (ACPI `ASCP1D80`) | The pressure-axis quirk applies here |
| Audio codec | Cirrus `CS42L43` + 2× `CS35L56` (subsystem `1043:15e4`) | Per-OEM speaker firmware needed |
| Wi-Fi card | Intel Wi-Fi 7 `BE211` (`8086:e440`) | iwlmld-mode tunables apply here |
| Distro | Arch / CachyOS / any Arch-derivative | The patcher uses `pacman` and reads `/etc` paths Arch-style |

If you're on a sibling model (`104315d4` / `104315f4`) and willing to test, see
[Adding a new module / model](#adding-a-new-module-or-model). If you're on a
different distro, the modules themselves still apply — only the
`pacman`-based package-install steps are Arch-specific.

## What this actually fixes — before / after

| Hardware | Symptom out of the box | After installing | Module |
|---|---|---|---|
| **PixArt I²C-HID** haptic touchpad `093A:4F05` (ACPI `ASCP1D80`) | **Touchpad doesn't move the cursor.** Kernel log spams `kernel bug: Touch jump detected and discarded.` libinput rejects every event. | Cursor responds to light touches like any normal laptop. Zero "Touch jump" lines. | [`touchpad-fix`](touchpad-fix/) |
| **Cirrus CS42L43** codec + 2× **CS35L56** speaker amps (PCI subsystem `1043:15e4`) | **Speakers are completely silent.** dmesg: `cs35l56: FIRMWARE_MISSING`, `Calibration disabled`. F1 mute LED stuck on. | Speakers play at any volume. dmesg: `Calibration applied`, `Tuning PID: 0x23134`. | [`audio-fix`](audio-fix/) |
| **Intel Wi-Fi 7 BE211** Panther Lake CNVi (`8086:e440`) | **Wi-Fi 7 (802.11be / EHT) is unstable.** EHT RX collapses to MCS0/NSS1, MLO sessions tear down, `missed beacons` spam, occasional `Microcode SW error` freezes. | EHT disabled (`disable_11be=Y`) → rock-solid **Wi-Fi 6 / HE** fallback (6 GHz, 160 MHz, ~2.1 Gbit/s verified). Zero beacon spam, no freezes. | [`wifi-fix`](wifi-fix/) |
| **Samsung Display Corp** eDP panel + Intel **`xe`** driver (Xe3 Panther Lake iGPU) | **Internal panel goes black.** `kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver`. eDP-1 wedges, only reboot recovers. | Internal display stable indefinitely. PSR / Panel Replay disabled cleanly at boot. | [`display-fix`](display-fix/) |
| **Intel Core Ultra X7/X9** Panther Lake hybrid (P + E + LP-E cores) | **Idle power 4–5 W**, fans audible at idle, P-cores never deep-sleep. | Idle ≈ 2–2.5 W. Workload parks on a single LP-E core. P-cores reach `C10`. | [`intel-perf-fix`](intel-perf-fix/) |
| **USB UVC webcam** (+ idle Panther Lake NPU) | **No AI camera effects.** Windows Studio Effects (background blur, smart framing) doesn't exist on Linux out of the box. | **CPU** background blur via OBS + `obs-backgroundremoval`, exposed as a virtual camera ("AI Camera"). *(NPU offload is not available in the OBS plugin on Linux — see the module's reality-check note.)* | [`webcam-ai-fix`](webcam-ai-fix/) |
| **ASUS BIOS `SLKB` ACPI method** (BIOS `B9406CAA.304`) | **KDE keyboard-backlight slider does nothing** — but the **Fn hotkeys still work** (the backlight is not dead). `SLKB` clamps OS-initiated `0..3` writes to `Local0 = Zero`, so KDE / `brightnessctl` / sysfs writes silently no-op. | *(optional)* KDE slider works: `asusd` translates kernel writes into the OEM-tested `0x100..0x103` range. | [`keyboard-backlight-fix`](keyboard-backlight-fix/) |

> **Nothing this repo installs is a band-aid in the bad sense.** Every module
> uses the exact same upstream-recognised mechanism (udev hwdb, libinput
> quirks, modprobe.d, systemd-tmpfiles, NetworkManager dispatcher, ALSA UCM
> codec dirs) that distros use to support every other laptop. We just
> haven't been added to the canonical lists yet — the
> [`upstream-patches/`](upstream-patches/) folder is the path to that.

## Quick install

```sh
git clone https://github.com/burakgon/asus-expertbook-linux.git
cd asus-expertbook-linux
./patch.sh install-all
sudo reboot
```

After reboot:

```sh
./patch.sh status
```

You should see all seven modules `up to date` and their runtime checks green.

### Or pick à la carte

```sh
./patch.sh list                          # see what's available
./patch.sh install touchpad-fix audio-fix
./patch.sh diff display-fix              # preview before installing
./patch.sh uninstall wifi-fix            # back out anytime
```

### Or run the interactive menu

```sh
./patch.sh
```

Auto-elevates with `sudo`, lets you install / uninstall / diff / status by
typing single letters. Numbered table, color-coded state, cached.

```
=== asus_expertboot_linux patcher ===

  #   Module                  Version  Installed State          Description
  ----------------------------------------------------------------------------------
  1   audio-fix               2.1.0    2.1.0     up to date     Speakers + mics + clean panel
  2   display-fix             1.1.2    1.1.2     up to date     xe Panel Replay / PSR lockup
  3   intel-perf-fix          1.1.0    1.1.0     up to date     thermald + intel-lpmd
  4   keyboard-backlight-fix  1.1.0    1.1.0     up to date     (optional) KDE backlight slider
  5   touchpad-fix            1.1.1    1.1.1     up to date     PixArt 093A:4F05 pressure quirk
  6   webcam-ai-fix           1.1.0    1.1.0     up to date     OBS CPU background blur
  7   wifi-fix                2.0.0    2.0.0     up to date     BE211: disable broken EHT

Actions
  i <num>    install / update module (idempotent — re-runs post hooks)
  u <num>    uninstall module
  d <num>    diff source vs installed (omit num for all)
  s <num>    detailed status (omit num for all modules)
  I          install all modules
  up         update all currently-installed modules
  U          uninstall all modules
  r          refresh
  q          quit

>
```

## Modules

### 1. [`touchpad-fix`](touchpad-fix/) — light-touch cursor

<details><summary><b>The bug</b> — pressure axis mis-parsed by hid-multitouch</summary>

The kernel's HID descriptor parser inflates `ABS_MT_PRESSURE` max to **2601**
(literally the Y-axis max value, suggesting a parser typo) for this PixArt
haptic touchpad. Real hardware values top out around 1000. libinput's
pressure thresholds are calibrated against the kernel-reported max, so real
touches register at 1–6% of the bogus "max" — well below the activation
threshold. Result: every motion is rejected as a "kernel bug: Touch jump."

```
$ sudo dmesg | grep "Touch jump" | wc -l
1873                                    ← without the module
0                                       ← with the module
```

</details>

<details><summary><b>The fix</b> — udev hwdb pressure clamp + libinput quirk</summary>

| File | Path | What it does |
|---|---|---|
| `61-pixart-4f05-pressure-fix.hwdb` | `/etc/udev/hwdb.d/` | Clamps `EVDEV_ABS_18` (`ABS_PRESSURE`) and `EVDEV_ABS_3A` (`ABS_MT_PRESSURE`) to a sane range so libinput's pressure heuristics see usable values. |
| `99-asus-expertbook-pixart-4f05.quirks` (installs as `local-overrides.quirks`) | `/etc/libinput/` | Tells libinput to ignore the pressure axes entirely via `AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE`. Same shape as the shipped Asus UX302LA quirk. |

After install, `libinput quirks list /dev/input/event9` confirms the quirk
is loaded.

</details>

### 2. [`audio-fix`](audio-fix/) — speakers, headphones, mics (HiFi UCM)

<details><summary><b>The bug</b> — firmware, a UCM gap, and topology noise</summary>

1. The Cirrus CS35L56 speaker amps need per-OEM tuning firmware. As of
   `linux-firmware-cirrus >= 20260519` it ships upstream for `1043:15e4`; on
   anything older the amps boot `FIRMWARE_MISSING` and the bundled blobs fill in.
2. The card reports a **combined** sidecar-amp codec — `spk:cs35l56+cs42l43-spk`
   (or two `spk:` tags on older kernels). Stock `alsa-ucm-conf 1.2.15.x` has no
   UCM dir for it **and** its `SpeakerCodec` regex drops the trailing `-spk`, so
   `alsaucm` fails (`codecs/cs35l56+cs42l43/init.conf: -2`). WirePlumber then
   uses `stereo-fallback`, which plays to the **Jack** PCM (device 0), not the
   **Speaker** PCM (device 2) — silent speakers, even though `aplay -D plughw:0,2`
   works.
3. The generic SOF topology declares an unused `SSP2-BT` hardware-offload PCM
   with no firmware blob; WirePlumber's probe of it spams the kernel log
   (~40% of all kernel errors at boot).

```
$ sudo dmesg | grep cs35l56
cs35l56 sdw:0:2:01fa:3556:01:0: FIRMWARE_MISSING                    ← without
cs35l56 sdw:0:2:01fa:3556:01:1: FIRMWARE_MISSING                    ← without
─────────────────────────────────────────────────────────────────────────
cs35l56 sdw:0:2:01fa:3556:01:0: Calibration applied                 ← with
cs35l56 sdw:0:2:01fa:3556:01:0: Tuning PID: 0x23134, SID: 0x470200  ← with
```

</details>

<details><summary><b>The fix</b> — HiFi UCM + cs35l56 firmware (replaces the old pro-audio pin)</summary>

The proper fix is the upstream **HiFi UCM**, not a profile hack — named ports,
headphone-jack **auto-switching**, working volume + mic-mute LED. **It's upstream
as of `alsa-ucm-conf 1.2.16`**, so on 1.2.16+ this module installs only the
firmware + the SSP2-BT drop-in; the UCM rows below are dropped in **only as a
fallback on `alsa-ucm-conf < 1.2.16`** (and the `NoExtract` pin is removed
automatically once the package crosses 1.2.16).

| File | Path | What it does |
|---|---|---|
| `cs35l56-…-l2u{0,1}.{bin,wmfw}` | `/lib/firmware/cirrus/` | Per-OEM tuning + ROM 3.4.4→3.13.4 patch. **Fallback** — `linux-firmware-cirrus >= 20260519` now ships these. |
| `sof-soundwire.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | Upstream `alsa-ucm-conf` master: fixes the `SpeakerCodec` regex to keep the `-spk` suffix. Pinned via `NoExtract` so a partial upgrade can't revert it (both only on `alsa-ucm-conf < 1.2.16`). |
| `cs35l56+cs42l43-spk.conf`, `cs42l43-spk+cs35l56.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | The Speaker device for the combined codec — routes playback to `hw:,2` and the CS35L56 + CS42L43 amps. |
| `cs42l43-spk+cs35l56-init.conf` | `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/` | Combined codec init (control remap + LED attach). `module.sh` symlinks `cs35l56+cs42l43-spk` → this so both kernel names resolve. |
| `52-disable-bt-sco-offload.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Disables the dead `SSP2-BT` offload PCM so its probe stops spamming the log. Bluetooth audio (A2DP/HFP) still works via the PipeWire software path. |

> The **F1 speaker-mute LED can't be fixed from Linux** — this laptop exposes no
> speaker-mute LED device, only `platform::micmute` (which the HiFi UCM drives).

</details>

### 3. [`wifi-fix`](wifi-fix/) — BE211: disable broken EHT, stabilize Wi-Fi 6

<details><summary><b>The bug</b> — Wi-Fi 7 / EHT is broken on BE211</summary>

The core problem is **802.11be (EHT / Wi-Fi 7) itself** on the Intel BE211
(`8086:e440`) under `iwlwifi`/`iwlmld`: the EHT RX path collapses to
**MCS0 / NSS1** and MLO sessions tear down, so the "Wi-Fi 7" link is slower and
flakier than plain Wi-Fi 6. Not fixed upstream as of Linux 7.1-rc7. Two
secondary irritants pile on: `iwlmld` defaults to `power_scheme=2` (beacon-loss
recovery churn), and the `iwlwifi` TX-segmentation offload bug can throw
`Microcode SW error` under heavy traffic.

```
$ sudo dmesg | grep -E "missed beacons|Microcode SW error" | wc -l
2046                                    ← with EHT on
0                                       ← with disable_11be=Y (Wi-Fi 6 fallback)
```

</details>

<details><summary><b>The fix</b> — disable broken EHT, keep a stable Wi-Fi 6 link</summary>

**Core fix** — drop the broken 802.11be layer so the radio runs as rock-solid
Wi-Fi 6 (HE). Same approach Omarchy ships; verified at ~2.1 Gbit/s over 160 MHz
6 GHz HE here:

| File | Path | What it does |
|---|---|---|
| `iwlwifi-disable-eht.conf` | `/etc/modprobe.d/` | `options iwlwifi disable_11be=Y` — disables EHT / Wi-Fi 7; the link falls back to stable Wi-Fi 6 / HE. |

**Secondary tunables** (trim remaining HE-mode instability; they do **not** keep
Wi-Fi 7 alive):

| File | Path | What it does |
|---|---|---|
| `iwlmld-active.conf` | `/etc/modprobe.d/` | `options iwlmld power_scheme=1` — disables driver-side power-save loop. |
| `pcie-aspm-performance.conf` | `/etc/tmpfiles.d/` | Write `performance` to `/sys/module/pcie_aspm/parameters/policy` at boot. |
| `90-iwlwifi-no-offload` | `/etc/NetworkManager/dispatcher.d/` | `ethtool -K $iface tso off gso off gro off` on every `iwlwifi` up event. |

This is a deliberate **Wi-Fi 7 → Wi-Fi 6** downgrade — EHT is the problem on this
silicon. `iwlwifi.bt_coex_active=Y` is left alone, so Bluetooth keeps working.

</details>

### 4. [`display-fix`](display-fix/) — internal panel doesn't lock up

<details><summary><b>The bug</b> — xe driver hangs Panel Replay handshake</summary>

The Samsung Display Corp panel in this laptop reports IEEE OUI `00:aa:01` in
DPCD register 0x300 and supports Panel Replay Selective Update (Early
Transport). The `xe` driver's PSR idle wait times out on this panel firmware:

```
xe 0000:00:02.0: [drm] Selective fetch area calculation failed in pipe A   # every boot
xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state
xe 0000:00:02.0: [drm] *ERROR* [CRTC:151:pipe A] DSB 0 timed out waiting for idle
kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver
```

Once the display engine wedges, only a reboot recovers it — modeset cycle,
GPU GT0 reset, and runtime PSR-disable via debugfs all fail.

It's worse than a black panel. When the PSR2 **selective-fetch** path deadlocks
the DSB during heavy compositing (a screen capture is enough to trigger it), it
can take the whole **kernel** down — a silent hard hang with no oops, no MCE,
and an empty `pstore`/BERT. That software-DSB hang is distinct from the Lunar
Lake PMC-firmware crash, which *does* leave a `BERT: [Hardware Error]` record
and is **not** cured by disabling PSR.

</details>

<details><summary><b>The fix</b> — xe.enable_psr=0 on the kernel cmdline</summary>

| File | Path | What it does |
|---|---|---|
| `xe-disable-psr.conf` | `/etc/modprobe.d/` | Belt-and-suspenders for late module load. |
| (managed block) | `/etc/default/limine` | Appends `xe.enable_psr=0 xe.enable_psr2_sel_fetch=0 xe.enable_panel_replay=0` to the kernel cmdline. The post-install hook calls `limine-update` so the new params land in every kernel entry of `/boot/limine.conf`. Uninstall removes the block cleanly. |

This is **structurally identical to the per-device entry** the upstream
`drm-intel-next` branch is growing for Dell XPS 14/16. Our
[`upstream-patches/0001`](upstream-patches/) ports the same approach to a
proper `intel_dpcd_quirks[]` entry — once merged, this module becomes a
no-op and can be uninstalled.

There is **no dedicated upstream tracker** for this Panther Lake PSR2
selective-fetch / DSB hang; it's reproduced locally on `linux-cachyos 7.0.11`
and `linux-cachyos-rc 7.1-rc7`. (drm/xe #7513 — *"Lunar lake, rare shutdown
under load"* — is a **distinct** Lunar Lake PMC-firmware bug, not this one.) No
fix is merged on any current kernel, so the cmdline workaround is still required.

</details>

### 5. [`webcam-ai-fix`](webcam-ai-fix/) — Linux equivalent of Windows Studio Effects

<details><summary><b>The gap</b> — no Linux equivalent shipped on Panther Lake "AI PC" laptops</summary>

Windows Studio Effects on Copilot+ PCs runs background blur, smart framing,
eye-contact correction, and voice focus on the NPU. None of these are
shipped on Linux out of the box, even though the Intel Panther Lake NPU
itself is fully supported by the kernel (`intel_vpu` driver,
`/dev/accel/accel0` exposed) and the userspace stack (OpenVINO 2026,
level-zero) is available via the AUR.

Without this module the NPU sits idle, the webcam feed has no AI
processing, and there's no virtual-cam target for video chat apps to
read from.

</details>

<details><summary><b>The fix</b> — OBS pipeline + virtual cam + ML segmentation plugin</summary>

| File / package | Source | What it does |
|---|---|---|
| `v4l2loopback.conf` | `/etc/modules-load.d/` | Auto-load v4l2loopback at boot |
| `v4l2loopback-options.conf` | `/etc/modprobe.d/` | Persistent device config (`devices=1 video_nr=10 card_label='AI Camera' exclusive_caps=1`) |
| `v4l2loopback-dkms` package | `extra` | Kernel module providing the virtual cam |
| `obs-studio` package | `extra` | Capture + filter graph + virtual-cam writer |
| `obs-backgroundremoval` package | AUR | ML segmentation OBS plugin (ONNX models). **CPU-only on Linux** — its execution providers are CUDA / ROCm / MIGraphX; there is no OpenVINO/NPU path in the OBS plugin. |

The user is also added to the `render` group as defensive future-proofing
for stricter NPU device permissions. `/dev/accel/accel0` ships
world-writable today.

After install, the user opens OBS, adds a Video Capture Device source
pointing at the real webcam, attaches the Background Removal filter,
and starts the virtual camera. Any video chat app then sees the
processed feed as "AI Camera".

> **Reality check — no NPU offload in OBS on Linux.** `obs-backgroundremoval`
> has no OpenVINO/NPU execution provider on Linux (installing `openvino` does
> **not** add an "NPU" device); the filter runs on the **CPU** — fine for 720p30
> background blur. For an actual NPU route see
> [`ericjchang/linux-studio-effects`](https://github.com/ericjchang/linux-studio-effects)
> (OpenVINO + v4l2loopback), but it's validated on Arrow Lake, **not yet Panther
> Lake**, and installs via git + pip. Also: if another tool already uses
> v4l2loopback (e.g. `linuxdrop` on `video_nr=20`), this module's global
> `options` line collides — share one `devices=2 video_nr=10,20` config instead.

</details>

### 6. [`intel-perf-fix`](intel-perf-fix/) — Panther Lake idle / thermal

<details><summary><b>The bug</b> — kernel-default thermal throttle and idle scheduling are coarse on Panther Lake</summary>

Without a userspace thermal daemon, the kernel governor's only lever is
"cap CPU frequency". On Panther Lake's hybrid topology (P-cores + E-cores +
LP-E cores), a P/E-aware throttle is far smarter — it can park work on
slower cores instead of slowing everything down.

Without `intel-lpmd`, idle work spreads across multiple cores; with it,
all idle work concentrates on a single LP-E core and the P-cores deep-sleep.

</details>

<details><summary><b>The fix</b> — install + enable thermald and intel-lpmd</summary>

| Package | Source | Service | Effect |
|---|---|---|---|
| `thermald` | `extra` repo | `thermald.service` | P/E-core-aware thermal throttle. |
| `intel-lpmd` | `extra` / `cachyos` repo | `intel_lpmd.service` | Parks idle work on LP-E core, lets P-cores deep-sleep. |

Both coexist with the existing `power-profiles-daemon` (PPD handles user
profile, thermald handles thermal, intel-lpmd handles idle topology).

This module ships **no payload files** — it's purely package install + service
enable in the post-install hook. The patcher tracks it the same way it
tracks file-based modules (versioned, idempotent, status-checked).

</details>

### 7. [`keyboard-backlight-fix`](keyboard-backlight-fix/) — *(optional)* restore software/KDE backlight control

> **The backlight is not dead** — the **Fn hotkeys** toggle it fine (handled by
> the EC in hardware, bypassing the buggy ACPI path). This module is **optional**:
> it only restores *software* control (the KDE slider / `brightnessctl` / sysfs).

<details><summary><b>The bug (software side)</b> — ASUS BIOS clamps OS-initiated brightness writes to zero</summary>

The B9406CAA BIOS (`B9406CAA.304`) ships a broken `SLKB` ACPI method.
Disassembled from the live DSDT:

```c
Method (SLKB, 1, NotSerialized) {
    If    ((Arg0 >= 0x0100) && (Arg0 <= 0x0106)) { Local0 = (Arg0 - 0x0100) }
    ElseIf((Arg0 >= 0x80)   && (Arg0 <= 0x83))   { Local0 = (Arg0 - 0x80) * 0x21 ... }
    ElseIf((Arg0 >= Zero)   && (Arg0 <= 0x03))   { Local0 = Zero }   // ← BUG
    STBC (Zero, Local0)
    Return (One)
}
```

The mainline `asus-wmi` Linux driver writes the standard `0..3` kernel
range, which hits the third branch — and it **unconditionally clamps
`Local0` to zero** before passing to STBC (the EC command emitter). End
result: every KDE / `brightnessctl` / direct `/sys` write is silently
turned into "set brightness 0", and the keyboard backlight stays off.

The OEM-tested `0x100..0x103` range works correctly. Verified by hand
via `acpi_call`: invoking `\_SB.PC00.LPCB.EC0.SLKB 0x103` lights the
backlight.

</details>

<details><summary><b>The fix</b> — let the asusd userspace daemon translate the value range</summary>

| File / package | Path | What it does |
|---|---|---|
| `xyz.ljones.Asusd.service` | `/usr/share/dbus-1/system-services/` | D-Bus activation entry for `asusd`. The `asusd.service` systemd unit is `Type=dbus`, but ASUS doesn't ship the matching D-Bus service file — without it nothing ever auto-starts the daemon. |
| `acpi_call.conf` | `/etc/modules-load.d/` | Auto-load the `acpi_call` kernel module so `/proc/acpi/call` is available for direct ACPI invocations during debugging. |
| `asusctl` package | `extra` repo | Provides the `asusd` daemon. |
| `acpi_call-dkms` package | AUR | Optional. Kernel module exposing `/proc/acpi/call`. |
| `/etc/asusd/` directory | (created in post_install) | `asusd` refuses to start without it; the package leaves it absent. |

`asusd` translates standard kernel-level brightness writes into the
OEM-tested `0x100..0x103` range before invoking ACPI, side-stepping the
buggy branch. KDE PowerDevil's keyboard-brightness control then reaches
the EC correctly.

</details>

## How it works

The whole project is a small bash module manager (`patch.sh`, ~500 lines)
plus folders. Each subfolder containing a `module.sh` is a discoverable
module:

```
asus-expertbook-linux/
├── patch.sh                    # the manager
├── audio-fix/
│   ├── module.sh               # manifest: files + hooks + status check
│   ├── README.md
│   └── …                       # payload files
├── display-fix/  …
├── intel-perf-fix/  …
├── keyboard-backlight-fix/  …
├── touchpad-fix/  …
├── webcam-ai-fix/  …
├── wifi-fix/  …
├── upstream-patches/           # submission-ready upstream patches
│   └── 0001…0003.patch
├── docs/                       # the GitHub Pages site
└── scripts/
    └── check-hardware.sh       # one-shot compatibility check
```

A module's manifest declares files (source → destination), an optional
post-install hook, an optional status-check function, and a version. The
patcher records the installed version under
`/var/lib/asus_expertboot_patcher/<module>.version` so subsequent
operations know whether each module is `up to date`, `update available`,
`partial`, `untracked`, or `not installed`.

| Command | Effect |
|---|---|
| `./patch.sh` | Interactive menu; auto-elevates to root via sudo. |
| `./patch.sh list` | Quick table of every module + its current state. |
| `./patch.sh status [module…]` | Detailed status: file presence + runtime probe + service state. |
| `./patch.sh install [module…]` | Idempotent install. Re-running applies any source updates. |
| `./patch.sh update [module…]` | Alias for install. |
| `./patch.sh uninstall [module…]` | Remove files + run uninstall hook. |
| `./patch.sh diff [module…]` | Show what would change before installing. |
| `./patch.sh install-all` | Install every discoverable module. |
| `./patch.sh update-all` | Re-install only modules that aren't `up to date`. |
| `./patch.sh uninstall-all` | Tear down everything cleanly. |

## Kernel & distro compatibility

- **Linux 6.18+** for the haptic-touchpad kernel parser, the new `iwlmld`
  Wi-Fi 7 op-mode, the `xe` driver Panther Lake bringup, and the
  `cs35l56` driver. Anything older won't even probe most of this
  hardware.
- **Tested on:** `linux-cachyos 7.0.x`, `linux-cachyos-rc` through `7.1-rc7`
  (the `display-fix` PSR hang persists on all of them). Should work on
  `linux-lts 6.18.x` and `linux 7.0.x` Arch builds.
- **Distros:** Arch and Arch derivatives (CachyOS, EndeavourOS, Manjaro)
  all use the same `/etc/udev/hwdb.d`, `/etc/libinput`,
  `/etc/modprobe.d`, `/etc/wireplumber/wireplumber.conf.d` paths the
  modules write to.
- **Bootloader assumption (display-fix):** `limine` via
  `limine-mkinitcpio-hook`, where `/etc/default/limine` is the source of
  truth. If you use systemd-boot or GRUB, the module's cmdline-injection
  hook needs swapping; the modprobe.d half still works.

## Adding a new module or model

Drop a folder containing a `module.sh` next to `patch.sh`. The patcher
discovers it automatically. The smallest example is
[`touchpad-fix/module.sh`](touchpad-fix/module.sh):

```bash
MODULE_NAME="my-fix"
MODULE_DESC="One-line description"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "src-relative-to-module-dir:/absolute/dst/path"
)

module_post_install()   { …; }   # optional
module_post_uninstall() { …; }   # optional
module_status_extra()   { …; }   # optional
```

Sibling-model contributions for `1043:15d4` and `1043:15f4` ExpertBook
Ultra variants are very welcome — open a PR with your subsystem ID's
firmware blobs (if cs35l56 is the same chip family) and any DMI tweaks
needed.

## Upstream submissions

The [`upstream-patches/`](upstream-patches/) folder ships three patches
that turn each module into a permanent upstream entry:

| # | Tree | Replaces |
|---|---|---|
| `0001` | `drivers/gpu/drm/i915/display/intel_quirks.c` | `display-fix`'s cmdline workaround |
| `0002` | `sound/soc/intel/boards/sof_sdw.c` | most of `audio-fix` (combined-codec UCM routing) |
| `0003` | `libinput/quirks/30-vendor-pixart.quirks` | `touchpad-fix`'s libinput override |

All three dry-run apply cleanly against current `torvalds/linux` master /
`drm-intel-next` / libinput main. See
[`upstream-patches/README.md`](upstream-patches/README.md) for hardware
identifiers, mailing list addresses, and submission instructions.

## License

[MIT](LICENSE) for the code (scripts, configs, patches).

Firmware files redistributed under `audio-fix/` come verbatim from upstream
[linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) under
their original Cirrus Logic redistribution license. See [NOTICE](NOTICE).

## FAQ

<details><summary><b>Does this work on similar 2026 ExpertBook Ultra models?</b></summary>

Most of it transfers. The `audio-fix` firmware blobs are matched on PCI
subsystem `1043:15e4` (this exact laptop). Sibling subsystems
`104315d4` and `104315f4` ship different per-OEM tuning files in
upstream `linux-firmware`. The `touchpad-fix`, `wifi-fix`,
`display-fix`, `intel-perf-fix`, `webcam-ai-fix`, and
`keyboard-backlight-fix` modules are hardware-agnostic or match by
family-level identifiers and apply more broadly.

PRs adding `module.sh` entries for sibling models are welcome.

</details>

<details><summary><b>Does this break Bluetooth?</b></summary>

No. The Wi-Fi module deliberately leaves `iwlwifi.bt_coex_active=Y` alone.
Bluetooth audio, HID, and file transfer keep working as usual.

</details>

<details><summary><b>Does this downgrade Wi-Fi 7?</b></summary>

**Yes — on purpose.** 802.11be / EHT is broken on the BE211 (RX collapses to
MCS0/NSS1, MLO tears down), so `wifi-fix` disables it (`disable_11be=Y`) and the
link runs as stable **Wi-Fi 6 / HE** instead — ~2.1 Gbit/s over 160 MHz 6 GHz
here, faster in practice than the flaky EHT link. Drop the module (or set
`disable_11be=N`) once Intel fixes the iwlwifi EHT path upstream.

</details>

<details><summary><b>What about the F1 mute LED?</b></summary>

The HiFi UCM (active since `audio-fix v2.0.0`, and upstream in
`alsa-ucm-conf 1.2.16`) drives the **mic-mute** LED (`platform::micmute`)
correctly. The **speaker-mute** LED (F1) stays in its EC default state
because this laptop exposes no speaker-mute LED device to Linux at all —
there's nothing for the UCM `SetLED` hook to bind to. It's a
missing-device limitation, not a profile issue.

</details>

<details><summary><b>Why not just upstream all of this and skip the repo?</b></summary>

That's the goal — see [`upstream-patches/`](upstream-patches/). Two of the
audio pieces already landed: `alsa-ucm-conf 1.2.16` ships the
`cs42l43-spk+cs35l56` codec dir and `linux-firmware-cirrus >= 20260519`
ships the OEM blobs, so on an up-to-date system `audio-fix` is already down
to a single topology-noise drop-in. As the kernel/quirk patches in
`upstream-patches/` land and your distro picks them up, every module here
becomes deletable.

</details>

<details><summary><b>How do I test changes before installing?</b></summary>

```sh
./patch.sh diff <module>          # show before/after on every file the module manages
```

Output marks each file as `unchanged` / `would update` / `would create`
with a coloured unified-diff for the changed ones.

</details>

## Acknowledgements

- [linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) for the
  upstream CS35L56 OEM tuning blobs.
- [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) for the
  shipped `cs35l56`, `cs42l43`, and `cs42l43-dmic` codec dirs that the
  combined `cs42l43-spk+cs35l56/init.conf` borrows from.
- [Omarchy](https://github.com/basecamp/omarchy) for surfacing how Panther
  Lake bring-up looks on the Hyprland side and which userspace daemons
  (thermald + intel-lpmd) are worth installing.
- The [libinput](https://gitlab.freedesktop.org/libinput/libinput) project
  for the Asus UX302LA quirk pattern that `touchpad-fix` mirrors.
