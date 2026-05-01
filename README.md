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
different distro, the modules themselves still apply — only the AUR / paru
parts of `intel-perf-fix` are Arch-specific.

## What this actually fixes — before / after

| Hardware | Symptom out of the box | After installing | Module |
|---|---|---|---|
| **PixArt I²C-HID** haptic touchpad `093A:4F05` (ACPI `ASCP1D80`) | **Touchpad doesn't move the cursor.** Kernel log spams `kernel bug: Touch jump detected and discarded.` libinput rejects every event. | Cursor responds to light touches like any normal laptop. Zero "Touch jump" lines. | [`touchpad-fix`](touchpad-fix/) |
| **Cirrus CS42L43** codec + 2× **CS35L56** speaker amps (PCI subsystem `1043:15e4`) | **Speakers are completely silent.** dmesg: `cs35l56: FIRMWARE_MISSING`, `Calibration disabled`. F1 mute LED stuck on. | Speakers play at any volume. dmesg: `Calibration applied`, `Tuning PID: 0x23134`. | [`audio-fix`](audio-fix/) |
| **Intel Wi-Fi 7 BE211** Panther Lake CNVi (`8086:e440`) | **Wi-Fi 7 link unstable.** Kernel log spams `missed beacons exceeds threshold, but receiving data`. Throughput drops, occasional `Microcode SW error` 10 second freezes. | Stable Wi-Fi 7 / 6 GHz / 320 MHz link. Zero missed-beacon spam. No freezes under heavy load. | [`wifi-fix`](wifi-fix/) |
| **Samsung Display Corp** eDP panel + Intel **`xe`** driver (Xe3 Panther Lake iGPU) | **Internal panel goes black.** `kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver`. eDP-1 wedges, only reboot recovers. | Internal display stable indefinitely. PSR / Panel Replay disabled cleanly at boot. | [`display-fix`](display-fix/) |
| **Intel Core Ultra X7/X9** Panther Lake hybrid (P + E + LP-E cores) | **Idle power 4–5 W**, fans audible at idle, P-cores never deep-sleep. | Idle ≈ 2–2.5 W. Workload parks on a single LP-E core. P-cores reach `C10`. | [`intel-perf-fix`](intel-perf-fix/) |
| **Intel Panther Lake NPU** (`8086:b03e`) + USB UVC webcam | **No AI camera effects.** Windows Studio Effects (background blur, smart framing, voice focus) doesn't exist on Linux out of the box. | Same effects via OBS + `obs-backgroundremoval` plugin, exposed as a virtual camera ("AI Camera") that any chat app can use. NPU-acceleration available with `paru -S openvino`. | [`webcam-ai-fix`](webcam-ai-fix/) |
| **ASUS BIOS `SLKB` ACPI method** (BIOS `B9406CAA.304`) | **Keyboard backlight slider in KDE does nothing.** `SLKB` clamps `Local0 = Zero` for the standard 0..3 brightness range that the kernel asus-wmi driver writes — so EC always gets brightness 0. Direct writes to `/sys/class/leds/asus::kbd_backlight/brightness` silently no-op. | KDE keyboard-brightness slider works. `asusd` userspace daemon translates kernel writes into the OEM-tested `0x100..0x103` range, which the BIOS handles correctly. | [`keyboard-backlight-fix`](keyboard-backlight-fix/) |

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

  #   Module             Version  Installed State          Description
  -----------------------------------------------------------------------------
  1   audio-fix          1.3.0    1.3.0     up to date     Speakers + mics + clean panel
  2   display-fix        1.1.1    1.1.1     up to date     xe Panel Replay PSR lockup
  3   intel-perf-fix     1.0.0    1.0.0     up to date     thermald + intel-lpmd
  4   touchpad-fix       1.1.0    1.1.0     up to date     PixArt 093A:4F05 pressure quirk
  5   wifi-fix           1.1.0    1.1.0     up to date     BE211 stability tweaks

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

### 2. [`audio-fix`](audio-fix/) — speakers, mics, clean sound panel

<details><summary><b>The bug</b> — three things stacked</summary>

1. The Cirrus CS35L56 speaker amps boot in `FIRMWARE_MISSING` state because
   `linux-firmware-cirrus < 20260410` doesn't ship the per-OEM `.bin` /
   `.wmfw` files for PCI subsystem `1043:15e4`.
2. ALSA UCM has no codec directory for the `cs42l43-spk+cs35l56` codec
   string this card advertises in `alsa.components`.
3. With both above, WirePlumber falls back to a generic `stereo-fallback`
   profile that doesn't route to the speaker output PCM at all.

```
$ sudo dmesg | grep cs35l56
cs35l56 sdw:0:2:01fa:3556:01:0: FIRMWARE_MISSING                    ← without
cs35l56 sdw:0:2:01fa:3556:01:1: FIRMWARE_MISSING                    ← without
─────────────────────────────────────────────────────────────────────────
cs35l56 sdw:0:2:01fa:3556:01:0: Calibration applied                 ← with
cs35l56 sdw:0:2:01fa:3556:01:0: Tuning PID: 0x23134, SID: 0x470200  ← with
```

</details>

<details><summary><b>The fix</b> — firmware blobs + UCM init + Pro Audio profile pin</summary>

| File | Path | What it does |
|---|---|---|
| `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.bin` | `/lib/firmware/cirrus/` | Per-OEM tuning blobs from upstream `linux-firmware`, applied to each amp via the chip's DSP. |
| `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.wmfw` | `/lib/firmware/cirrus/` | Generic CS35L56 firmware patch (Rev 3.13.4) renamed to per-OEM filename pattern so the chip ROM upgrades from 3.4.4 to 3.13.4. |
| `cs42l43-spk+cs35l56/init.conf` | `/usr/share/alsa/ucm2/codecs/` | Combined codec init that maps abstract speaker controls to concrete `AMP1` / `AMP2` switches. |
| `51-asus-expertbook-pro-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Pins the SoundWire card to the Pro Audio profile so PipeWire exposes a discrete Speaker sink. Hides Bluetooth + Deepbuffer noise. Renames raw PCMs to "Speaker (Internal)", "HDMI 1/2/3", "Headset Mic", "Internal Microphone". Sets `session.suspend-timeout-seconds=0` on the Speaker sink to avoid first-playback corruption. |

</details>

### 3. [`wifi-fix`](wifi-fix/) — BE211 stability without losing Wi-Fi 7

<details><summary><b>The bug</b> — three independent failure modes</summary>

1. **`iwlmld` defaults to `power_scheme=2`** (balanced power saving). Under
   marginal SNR the radio enters short power-saves, misses beacons, and
   trips the *"Stay connected, Expect bugs"* recovery path.
2. **PCIe ASPM L1.x wake latency** on integrated CNVi cards is enough to
   push some 802.11 timeouts past their threshold.
3. **`iwlwifi`'s TX-segmentation offload bug** under heavy traffic produces
   `Microcode SW error` and full 10-second system freezes.

```
$ sudo dmesg | grep -E "missed beacons|Microcode SW error" | wc -l
2046                                    ← without the module
0                                       ← with the module (over 4h of mixed use)
```

</details>

<details><summary><b>The fix</b> — three driver tunables, none of which downgrade the link</summary>

| File | Path | What it does |
|---|---|---|
| `iwlmld-active.conf` | `/etc/modprobe.d/` | `options iwlmld power_scheme=1` — disables driver-side power-save loop. |
| `pcie-aspm-performance.conf` | `/etc/tmpfiles.d/` | At every boot, write `performance` to `/sys/module/pcie_aspm/parameters/policy` (CNVi has no per-device knob). |
| `90-iwlwifi-no-offload` | `/etc/NetworkManager/dispatcher.d/` | On every `iwlwifi` interface up event, run `ethtool -K $iface tso off gso off gro off`. |

**Untouched on purpose:** band, channel width, Wi-Fi 7 protocol features,
`iwlwifi.bt_coex_active=Y` — Bluetooth keeps working.

</details>

### 4. [`display-fix`](display-fix/) — internal panel doesn't lock up

<details><summary><b>The bug</b> — xe driver hangs Panel Replay handshake</summary>

The Samsung Display Corp panel in this laptop reports IEEE OUI `00:aa:01` in
DPCD register 0x300 and supports Panel Replay Selective Update (Early
Transport). The `xe` driver's PSR idle wait times out on this panel firmware:

```
xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state
xe 0000:00:02.0: [drm] *ERROR* [CRTC:151:pipe A] DSB 0 timed out waiting for idle
kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver
```

Once the display engine wedges, only a reboot recovers it — modeset cycle,
GPU GT0 reset, and runtime PSR-disable via debugfs all fail.

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

</details>

### 5. [`webcam-ai-fix`](webcam-ai-fix/) — Linux equivalent of Windows Studio Effects

<details><summary><b>The gap</b> — no Linux equivalent shipped on Panther Lake "AI PC" laptops</summary>

Windows Studio Effects on Copilot+ PCs runs background blur, smart framing,
eye-contact correction, and voice focus on the NPU. None of these are
shipped on Linux out of the box, even though the Intel Panther Lake NPU
itself is fully supported by the kernel (`intel_vpu` driver,
`/dev/accel/accel0` exposed) and the userspace stack (OpenVINO 2026,
level-zero) is available in the repos.

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
| `obs-backgroundremoval` package | AUR | ML segmentation OBS plugin (ONNX models, can target NPU via OpenVINO) |
| `openvino` (optional) | AUR | Intel's official AI inference toolkit; enables NPU acceleration. ~30 min compile from source. |

The user is also added to the `render` group as defensive future-proofing
for stricter NPU device permissions. `/dev/accel/accel0` ships
world-writable today.

After install, the user opens OBS, adds a Video Capture Device source
pointing at the real webcam, attaches the Background Removal filter,
and starts the virtual camera. Any video chat app then sees the
processed feed as "AI Camera".

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
| `intel-lpmd` | AUR (`paru -S intel-lpmd`) | `intel_lpmd.service` | Parks idle work on LP-E core, lets P-cores deep-sleep. |

Both coexist with the existing `power-profiles-daemon` (PPD handles user
profile, thermald handles thermal, intel-lpmd handles idle topology).

This module ships **no payload files** — it's purely package install + service
enable in the post-install hook. The patcher tracks it the same way it
tracks file-based modules (versioned, idempotent, status-checked).

</details>

### 7. [`keyboard-backlight-fix`](keyboard-backlight-fix/) — work around the BIOS `SLKB` clamp bug

<details><summary><b>The bug</b> — ASUS BIOS clamps every kernel-side brightness write to zero</summary>

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
- **Tested on:** `linux-cachyos 7.0.x`, `linux-cachyos-rc 7.1-rc1`. Should
  work on `linux-lts 6.18.x` and `linux 7.0.x` Arch builds.
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
| `0002` | `sound/soc/intel/boards/sof_sdw.c` | most of `audio-fix` (UCM hack + Pro Audio pin) |
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

No. Wi-Fi 7 / 6 GHz / 320 MHz / EHT-MCS rates stay exactly as the card
prefers. The wifi-fix only disables the driver-side power-save loop,
the L1.x ASPM wake latency, and the buggy TX-segmentation offload —
none of which limits link speed.

</details>

<details><summary><b>What about the F1 mute LED?</b></summary>

Currently still in the EC firmware default state because we route audio
through the Pro Audio profile (which bypasses UCM `SetLED` hooks).
Once [`upstream-patches/0002`](upstream-patches/) lands and the kernel
selects a HiFi UCM profile for our card, the existing `SetLED`
bindings in `/usr/share/alsa/ucm2/codecs/cs35l56/init.conf` will
attach the LED to the AMP switches automatically and F1 will work.

</details>

<details><summary><b>Why not just upstream all of this and skip the repo?</b></summary>

That's the goal — see [`upstream-patches/`](upstream-patches/). Until
those land in `torvalds/linux` master, `linux-firmware` ships with the
right files in the right places, and `alsa-ucm-conf` ships the
`cs42l43-spk+cs35l56` codec dir, this repo is the gap-filler. When all
of that is upstream and your distro picks it up, every module here
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
