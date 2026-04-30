# asus-expertbook-linux

> Linux compatibility patches for the 2026 **ASUS ExpertBook Ultra B9406CAA**
> (Panther Lake) — packaged as a tracked, versioned patcher.

🌐 **Site / docs:** <https://burakgon.github.io/asus-expertbook-linux/>

Out of the box on Linux 6.18+ / 7.x, three things on this laptop don't work
properly:

| Problem | Symptom | Module |
|---|---|---|
| PixArt `093A:4F05` haptic touchpad | Cursor never moves; libinput logs `kernel bug: Touch jump detected` | [`touchpad-fix`](touchpad-fix/) |
| Cirrus `CS35L56` speaker amplifiers (subsystem `1043:15e4`) | Speakers silent; `FIRMWARE_MISSING` in dmesg | [`audio-fix`](audio-fix/) |
| Intel **Wi-Fi 7 BE211** (`iwlmld`) | `missed beacons exceeds threshold` spam, drops, freezes | [`wifi-fix`](wifi-fix/) |

Each is a small userspace fix. None require kernel patches, none replace
firmware blobs your distro doesn't already redistribute, and none downgrade
hardware capabilities (Wi-Fi 7 stays Wi-Fi 7, Bluetooth coex stays on, the
haptic pad stays haptic).

## Quick install

```sh
git clone https://github.com/burakgon/asus-expertbook-linux.git
cd asus-expertbook-linux
./patch.sh install-all
sudo reboot
```

Or pick modules à la carte:

```sh
./patch.sh list
./patch.sh install touchpad-fix audio-fix
./patch.sh status
```

Or run interactively:

```sh
./patch.sh
```

## The patcher

`patch.sh` is a tiny module manager (~400 lines of bash). Each subfolder
that contains a `module.sh` is a module. The manifest declares the files to
install, where they go, and optional pre/post hooks.

| Command | What it does |
|---|---|
| `./patch.sh` | Interactive menu. Re-execs under sudo automatically. |
| `./patch.sh list` | Discover modules with at-a-glance install state. |
| `./patch.sh status [<module>...]` | Detailed: file presence + runtime check. |
| `./patch.sh install <module>...` | Idempotent install. Re-running applies updates. |
| `./patch.sh update <module>...` | Alias for install. |
| `./patch.sh uninstall <module>...` | Remove files + run uninstall hook. |
| `./patch.sh diff [<module>...]` | Show what would change before installing. |
| `./patch.sh install-all` | Install every module. |
| `./patch.sh update-all` | Re-install only `update-available` / `partial` / `untracked` modules. |
| `./patch.sh uninstall-all` | Tear everything down. |

Installed module versions are tracked under
`/var/lib/asus_expertboot_patcher/<module>.version` so the patcher can tell
when an update is available.

## Modules

### touchpad-fix

PixArt `093A:4F05` haptic touchpad. The kernel mis-reports the pressure
axis range, so libinput rejects every touch as a "Touch jump." Fix uses two
files:

- `/etc/udev/hwdb.d/61-pixart-4f05-pressure-fix.hwdb` — clamps the pressure
  axis to a sane range via `EVDEV_ABS_*`.
- `/etc/libinput/local-overrides.quirks` — tells libinput to ignore the
  pressure axis entirely (same shape as the shipped Asus UX302LA quirk).

### audio-fix

Cirrus `CS35L56` speaker amps boot in `FIRMWARE_MISSING` because
`linux-firmware-cirrus` doesn't ship the per-OEM tuning files for PCI
subsystem `1043:15e4`. ALSA UCM is missing the
`cs42l43-spk+cs35l56` codec dir. WirePlumber falls back to an unrouted
`stereo-fallback` profile.

This module bundles:

- `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.bin` — per-OEM tuning blobs
  (upstream linux-firmware).
- `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.wmfw` — generic
  `CS35L56_Rev3.13.4.wmfw` from upstream, renamed to the per-OEM filename
  pattern. Patches the chip ROM 3.4.4 → 3.13.4 so the bins load cleanly
  and calibration applies.
- `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf` — minimal
  combined codec init (control remap + speaker LED hooks).
- `/etc/wireplumber/wireplumber.conf.d/51-asus-expertbook-pro-audio.conf` —
  pins the card to Pro Audio, hides the Bluetooth and Deepbuffer raw
  sinks, gives Speaker / Headphone / HDMI / Mic friendly names.

### wifi-fix

Intel Wi-Fi 7 `BE211` (`iwlmld` op_mode). Three independent driver
tunables addressing three independent failure modes:

- `/etc/modprobe.d/iwlmld-active.conf` — `options iwlmld power_scheme=1`,
  disables driver-side power saving.
- `/etc/tmpfiles.d/pcie-aspm-performance.conf` — pins global PCIe ASPM to
  `performance` at every boot. (CNVi has no per-device ASPM knobs.)
- `/etc/NetworkManager/dispatcher.d/90-iwlwifi-no-offload` — disables
  TSO/GSO/GRO on `iwlwifi` interfaces to side-step the segmentation-offload
  bug that triggers `Microcode SW error` freezes.

**Does not** touch `bt_coex_active`, the band, channel width, or protocol.

## Adding a new module

Drop a folder containing a `module.sh` next to `patch.sh`. The patcher
picks it up automatically. The smallest example is `touchpad-fix/module.sh`:

```bash
MODULE_NAME="my-fix"
MODULE_DESC="One-line description"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "src-relative-to-module-dir:/absolute/dst/path"
)

module_post_install() { ... }
module_post_uninstall() { ... }
module_status_extra() { ... }
```

PRs adding fixes for sibling ASUS models (`104315d4`, `104315f4`) are
welcome.

## License

[MIT](LICENSE) for the code (scripts, configs).

Firmware blobs under `audio-fix/` are redistributed verbatim from upstream
[linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware) under
their original Cirrus Logic redistribution license; see [NOTICE](NOTICE).

When the upstream `linux-firmware` package picks up the per-OEM files for
`cs35l56-b0-dsp1-misc-104315e4-*` and `alsa-ucm-conf` ships a real
`cs42l43-spk+cs35l56` codec dir, this entire repo becomes deletable.
