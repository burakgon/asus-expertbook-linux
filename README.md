<div align="center">

# asus-expertbook-linux

**Linux compatibility patches for the 2026 ASUS ExpertBook Ultra (B9406CAA)** —
tracked and versioned, with reversible configuration modules plus an explicitly
confirmed camera-firmware capsule update.

[![GitHub Pages](https://img.shields.io/badge/site-burakgon.github.io-7dd3fc?style=flat-square)](https://burakgon.github.io/asus-expertbook-linux/)
[![License: MIT](https://img.shields.io/badge/license-MIT-c4b5fd?style=flat-square)](LICENSE)
[![Linux 6.18+](https://img.shields.io/badge/linux-6.18%2B-86efac?style=flat-square)](#kernel--distro-compatibility)
[![Hardware](https://img.shields.io/badge/hardware-B9406CAA-fbbf24?style=flat-square)](#is-this-repo-for-me)
[![No kernel rebuild required](https://img.shields.io/badge/kernel%20rebuild-not%20required-86efac?style=flat-square)](#how-it-works)

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
| Laptop model (DMI) | `ASUS EXPERTBOOK B9406CAA` | The fixes are written and tested for this model. `ish-firmware`, `camera-firmware` and `touchpad-haptics` refuse other hardware, and the audio overlay's quirk only matches this board's DMI |
| CPU family | Intel Core Ultra Series 3 (Panther Lake) | Required for the `xe` driver / `iwlmld` paths |
| Touchpad | PixArt I²C-HID `093A:4F05` (ACPI `ASCP1D80`) | The pressure-axis quirk applies here |
| Audio codec | Cirrus `CS42L43` + 2× `CS35L56` (subsystem `1043:15e4`) | Per-OEM speaker firmware needed |
| Wi-Fi card | Intel Wi-Fi 7 `BE211` (`8086:e440`) | iwlmld-mode tunables apply here |
| Ambient light sensor | `iio` device named `als` with `in_illuminance_raw` | `keyboard-backlight-auto` reads it to drive the keyboard backlight |
| Intel Sensor Hub | PCI `8086:e445` with `/sys/bus/ishtp/devices` populated | The `als` device only exists once the ISH runs ASUS's signed image; `ish-firmware` installs it |
| Distro | Arch / CachyOS / any Arch-derivative — Debian / Ubuntu / Pop!_OS partially | Every module works on Arch; on Debian families see the [support table](#kernel--distro-compatibility) |

If you're on a sibling model (`104315d4` / `104315f4`) and willing to test, see
[Adding a new module / model](#adding-a-new-module-or-model). If you're on a
Debian-family distro, see the per-module status in
[Kernel & distro compatibility](#kernel--distro-compatibility) — the config-file
modules apply as-is, and the package-installing ones are being ported one at a
time via [`lib/distro.sh`](lib/distro.sh).

## What this actually fixes — before / after

| Hardware | Symptom out of the box | After installing | Module |
|---|---|---|---|
| **PixArt I²C-HID** haptic touchpad `093A:4F05` (ACPI `ASCP1D80`) | **Touchpad doesn't move the cursor.** Kernel log spams `kernel bug: Touch jump detected and discarded.` libinput rejects every event. A separate `i2c_designware.0` wedge can freeze the whole desktop; see [below](#if-the-desktop-freezes). | Cursor responds to light touches like any normal laptop. Zero "Touch jump" lines. The bus wedge is a kernel stall the quirk does not prevent. | [`touchpad-fix`](touchpad-fix/) |
| **PixArt haptic touchpad** (Windows Precision pressure pad) | **No click-force or haptic-strength setting.** MyASUS sets both on Windows; Linux has no control, and the firmware forgets them at power-off. | *(optional)* `touchpad-haptics set --click-force light --intensity 30`, saved values restored whenever the pad appears. Standard HID feature reports only, verified against the pad's descriptor. | [`touchpad-haptics`](touchpad-haptics/) |
| **F1 / F4 mute indicator LEDs** | Audio mute works, but the orange lights do not follow it. Linux 7.2 has no `platform::mute` for this board. | A DKMS bridge registers the speaker LED with the `audio-mute` trigger on kernels before 7.4. Speaker and microphone sync can be enabled separately. | [`mute-led-fix`](mute-led-fix/) |
| **Cirrus CS42L43** codec + 2× **CS35L56** speaker amps (PCI subsystem `1043:15e4`) | **Dummy Output / silent speakers.** A ghost RT722 can abort ALSA card registration; older userspace also lacks tuning/UCM. | Uses the accepted in-kernel B9406 quirk when present and DKMS only on older kernels; HiFi routing and calibrated amps work. | [`audio-fix`](audio-fix/) |
| **Intel Wi-Fi 7 BE211** Panther Lake CNVi (`8086:e440`) | **Wi-Fi 7 (802.11be / EHT) is unstable.** EHT RX can collapse to MCS0/NSS1 and MLO sessions tear down. Linux 7.2's C106 firmware may separately flood `missed beacons` warnings even while data flows. | EHT disabled (`disable_11be=Y`) → fast **Wi-Fi 6 / HE** fallback; status reports firmware and warning count without hiding logs or forcing a firmware downgrade. | [`wifi-fix`](wifi-fix/) |
| **Samsung Display Corp** eDP panel + Intel **`xe`** driver (Xe3 Panther Lake iGPU) | **Linux 7.2's Panel Replay default misbehaves on this panel:** PSR idle timeouts with on-screen corruption, flicker, VRR smearing, stale frames, and HDR washed out after every HDR modeset. Brightness can also change in sysfs without changing panel luminance. | Self-refresh pinned to PSR1: owners report no flicker, stale frames or VRR smearing, and HDR stays vivid across toggles; forced VESA DPCD backlight makes KDE/sysfs brightness work. | [`display-fix`](display-fix/) |
| **Samsung OLED HDR** (EDID HDR metadata inside DisplayID 2.0) | **KDE offers no HDR toggle.** libdisplay-info 0.3.0 never looks inside the DisplayID 2.0 extension where this panel declares PQ, 1600 cd/m² and BT.2020, so KWin sees an SDR panel. | *(optional)* The upstream commits that read DisplayID 2.0 CTA blocks, backported onto 0.3.0 with two parser fixes of our own and the `.so.3` ABI intact, preferred through `ld.so.conf.d`; HDR appears in Display & Monitor. A pacman hook retires it whenever the distro's package changes. | [`hdr-fix`](hdr-fix/) |
| **Intel Core Ultra X7/X9** Panther Lake hybrid (P + E + LP-E cores) | **No userspace thermal policy:** the OEM's adaptive thermal tables (PL1/PL2 limits, passive trips) are not applied; only the kernel's int340x sensors and limits are exposed. | `thermald` runs the OEM tables in adaptive mode. `intel-lpmd` is opt-in: on Panther Lake it showed no significant idle gain and slowed app launches. | [`intel-perf-fix`](intel-perf-fix/) |
| **Platform profiles** (Intel SoC Power Slider + asus-wmi) | **Power Save only reaches `balanced`**, and from Performance it snaps back to Balanced. The legacy profile file lists only the choices both handlers share, so the SoC slider never goes low-power and the fans never go quiet. | Power Save sets the SoC slider to `low-power` and asus-wmi to `quiet` and stays there; Balanced and Performance map one-to-one. power-profiles-daemon stays in charge of the profile and CPU EPP. | [`power-profile-bridge`](power-profile-bridge/) |
| **USB UVC webcam** (+ idle Panther Lake NPU) | **No AI camera effects.** Windows Studio Effects (background blur, smart framing) doesn't exist on Linux out of the box. | **CPU** background blur via OBS + `obs-backgroundremoval`, exposed as a virtual camera ("AI Camera"). *(NPU offload is not available in the OBS plugin on Linux — see the module's reality-check note.)* | [`webcam-ai-fix`](webcam-ai-fix/) |
| **Shinetech USB camera + UEFI ESRT target** | ASUS camera firmware 3009 is distributed as a Windows EXE. | Compares locally against the fixed, verified 3009 baseline; offers a confirmed `fwupd` capsule update without running Windows or querying ASUS for newer versions. | [`camera-firmware`](camera-firmware/) |
| **Intel Sensor Hub** (`8086:e445`, carries the ambient light sensor) | **No ambient light sensor at all.** The kernel's generic `ish_ptl.bin` is rejected (`ISH loader: cmd 2 failed 10`); linux-firmware has no ASUS image, so `/sys/bus/iio` never gets an `als` device. | The ASUS-signed image from ASUS's own Sensor Hub driver package is verified and installed under the per-OEM name the kernel requests; `iio:device1 = als` appears and `keyboard-backlight-auto` has a sensor to read. | [`ish-firmware`](ish-firmware/) |
| **Ambient light sensor** (`iio` `als`) + keyboard backlight | **The backlight never adapts to the room.** KDE PowerDevil reads the sensor for *screen* brightness only; the keyboard stays wherever the Fn keys left it, and comes up dark after every boot. | *(optional)* The backlight follows the room using Windows 11's documented ALR curve — dim in the dark, brightest around 40–100 lux, off above 200–300 lux. Forced off with the lid shut; Fn keys still take over. | [`keyboard-backlight-auto`](keyboard-backlight-auto/) |
| **ASUS BIOS `SLKB` ACPI method** (BIOS `B9406CAA.312`) | **Keyboard brightness reads back as `0`** no matter what it was set to — sysfs, UPower and `brightnessctl` all report a dark keyboard, and `systemd-backlight` restores `0` at every boot. Writes themselves reach the EC fine. | *(superseded)* Nothing to fix on the write path: the v1.x `asusd` workaround targeted an ACPI branch mainline `asus-wmi` never reaches. Kept for older firmware, skips install by default. | [`keyboard-backlight-fix`](keyboard-backlight-fix/) |

> **Nothing this repo installs is a band-aid in the bad sense.** Every module
> uses the exact same upstream-recognised mechanism (udev hwdb, libinput
> quirks, modprobe.d, systemd-tmpfiles, NetworkManager dispatcher, ALSA UCM
> codec dirs) that distros use to support every other laptop. We just
> haven't been added to the canonical lists yet — the
> [`upstream-patches/`](upstream-patches/) folder is the path to that.

## If the desktop freezes

Two different failures end in a frozen desktop on this laptop. The runbook
[`docs/b9406-desktop-freeze.md`](docs/b9406-desktop-freeze.md) has the
commands that tell them apart, the logged incidents and the recovery steps.

- **Display self-refresh.** The kernel log shows `Timed out waiting PSR idle
  state`, DSB errors or FIFO underruns. Install `display-fix` 1.4 and reboot;
  it pins self-refresh to PSR1.
- **Touchpad I²C wedge.** The PixArt touchpad sits on `i2c_designware.0`.
  When that controller wedges, the log shows `controller timed out`, then
  `timeout in disabling adapter`, then `timeout waiting for bus ready` about
  twenty times a second. The touchpad IRQ thread and `i915_flip` workers sit
  in `D` state, so the picture stops as well. It was logged on
  `linux 7.2.3-arch1-3` at the end of long sessions, once within a minute of
  a resume, with no PSR or DSB error in the journal. `touchpad-fix` does not
  prevent it. While the session still accepts a command, rebind the touchpad
  driver (`omarchy restart trackpad` on Omarchy):

  ```sh
  dev=i2c-ASCP1D80:00
  echo "$dev" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
  sleep 1
  echo "$dev" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
  ```

  If the rebind hangs, or the picture is already frozen, reboot. Do not poll
  `acpitz` or ASUS `hwmon` fan/temperature nodes from a status bar: the
  reporter isolated a recurring stall to a widget doing exactly that.

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

You should see all fourteen modules `up to date` (or not applicable) and their runtime
checks green — except `keyboard-backlight-fix`, which reports `not installed`
because it deliberately supersedes itself.

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

  #   Module                    Version    Installed  State          Description
  --------------------------------------------------------------------------------------
  1   audio-fix                 3.2.0      3.2.0      up to date     Adaptive ghost-RT722 fix + HiFi audio
  2   camera-firmware           3009       3009       up to date     Verified camera UEFI capsule
  3   display-fix               1.4.0      1.4.0      up to date     PSR1 self-refresh + DPCD brightness
  4   hdr-fix                   1.0.0      1.0.0      up to date     DisplayID 2.0 HDR metadata for KWin
  5   intel-perf-fix            1.3.0      1.3.0      up to date     thermald (+ opt-in intel-lpmd)
  6   ish-firmware              5.8.1.7783 5.8.1.7783 up to date     ASUS Sensor Hub image (ambient light)
  7   keyboard-backlight-auto   1.3.0      1.3.0      up to date     Ambient-light keyboard backlight
  8   keyboard-backlight-fix    2.0.0      -          not installed  (superseded) asusd workaround
  9   power-profile-bridge      1.0.0      1.0.0      up to date     Power-saver → SoC low-power + quiet fans
  10  touchpad-fix              1.2.1      1.2.1      up to date     PixArt 093A:4F05 pressure quirk
  11  touchpad-haptics          1.0.0      1.0.0      up to date     Click force + haptic intensity
  12  webcam-ai-fix             1.1.0      1.1.0      up to date     OBS CPU background blur
  13  wifi-fix                  2.1.1      2.1.1      up to date     BE211: EHT fallback + beacon diagnostics

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

<details><summary><b>The bug</b> — the pad's descriptor gives pressure the Y axis's maximum</summary>

The pad's HID report descriptor gives Tip Pressure no Logical Maximum of its
own, so it inherits the Y field's **2601** and the kernel reports that as the
`ABS_MT_PRESSURE` maximum. Real presses sit far below it, so libinput's
pressure thresholds never see a proper touch and every motion is rejected as a
"kernel bug: Touch jump." The sister pad `093A:4811` was fixed upstream in
libinput 1.32 with `AttrInputProp=+INPUT_PROP_PRESSUREPAD`; `4F05` has no
upstream entry yet.

```
$ journalctl -b | grep -c "Touch jump"   # libinput logs through the compositor
1873                                    ← without the module
0                                       ← with the module
```

</details>

<details><summary><b>The fix</b> — udev hwdb pressure clamp + libinput quirk</summary>

| File | Path | What it does |
|---|---|---|
| `61-pixart-4f05-pressure-fix.hwdb` | `/etc/udev/hwdb.d/` | Clamps `EVDEV_ABS_18` (`ABS_PRESSURE`) and `EVDEV_ABS_3A` (`ABS_MT_PRESSURE`) to a sane range so libinput's pressure heuristics see usable values. |
| `99-asus-expertbook-pixart-4f05.quirks` (managed block in `local-overrides.quirks`) | `/etc/libinput/` | Tells libinput to ignore the pressure axes entirely via `AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE`. Same shape as the shipped Asus UX302LA quirk. Since 1.2.0 it is written as a marked block, so other overrides in that shared file survive install and uninstall. |

After install, `libinput quirks list /dev/input/event9` confirms the quirk
is loaded.

</details>

### 2. [`audio-fix`](audio-fix/) — speakers, headphones, mics (HiFi UCM)

<details><summary><b>The bug</b> — a ghost codec, firmware, a UCM gap, and topology noise</summary>

1. B9406CAA firmware describes an unfitted RT722. Kernels that retain its
   `UNATTACHED` endpoint create a duplicate `SDW3-Playback-SimpleJack`, abort
   `sof_sdw` with `-EEXIST`/`-12`, and expose no ALSA card at all.
2. The Cirrus CS35L56 speaker amps need per-OEM tuning firmware. As of
   `linux-firmware-cirrus >= 20260519` it ships upstream for `1043:15e4`; on
   anything older the amps boot `FIRMWARE_MISSING` and the bundled blobs fill in.
   This unit has no `CirrusSmartAmpCalibrationData` EFI variable, so the kernel
   skips per-unit calibration silently and no "Calibration applied" line
   appears; the tuning still loads.
3. The card reports a **combined speaker-codec** string — `spk:cs35l56+cs42l43-spk`
   (or two `spk:` tags on older kernels). Stock `alsa-ucm-conf 1.2.15.x` has no
   UCM dir for it **and** its `SpeakerCodec` regex drops the trailing `-spk`, so
   `alsaucm` fails (`codecs/cs35l56+cs42l43/init.conf: -2`). WirePlumber then
   uses `stereo-fallback`, which plays to the **Jack** PCM (device 0), not the
   **Speaker** PCM (device 2) — silent speakers, even though `aplay -D plughw:0,2`
   works.
4. On kernels before 7.1 the generic SOF topology declares an unused `SSP2-BT`
   hardware-offload PCM with no firmware blob; WirePlumber's probe of it spams
   the kernel log (~40% of all kernel errors at boot). The 7.1+ function
   topologies no longer expose it.
5. SOF firmware and topologies are the separate `sof-firmware` package. A
   minimal install can lack it, and then no card appears even with the
   ghost-RT722 fix (`SOF firmware and/or topology file not found`).

```
$ sudo dmesg | grep cs35l56
cs35l56 sdw:0:2:01fa:3556:01:0: FIRMWARE_MISSING                         ← without
cs35l56 sdw:0:2:01fa:3556:01:1: FIRMWARE_MISSING                         ← without
──────────────────────────────────────────────────────────────────────────────
cs35l56 sdw:0:2:01fa:3556:01:0: DSP1: Firmware: 1a00d6 vendor: 0x2 v3.13.4, 41 algorithms  ← with
cs35l56 sdw:0:2:01fa:3556:01:0: Tuning PID: 0x23134, SID: 0x470200, TID: 0x84b06           ← with
```

</details>

<details><summary><b>The fix</b> — adaptive upstream/DKMS ghost filter + HiFi UCM + cs35l56 firmware</summary>

The proper fix is the upstream **HiFi UCM**, not a profile hack — named ports,
headphone-jack **auto-switching**, working volume + mic-mute LED. **It's upstream
as of `alsa-ucm-conf 1.2.16`**, and the speaker firmware is upstream as of
`linux-firmware-cirrus 20260519`. On current packages this module therefore
installs only the SSP2-BT drop-in and, where needed, the DKMS overlay; the UCM
and firmware rows below are dropped in **only as a fallback on older
packages** (the `NoExtract` pin is removed automatically once `alsa-ucm-conf`
crosses 1.2.16). Install also pulls in `sof-firmware` when it is missing.

3.2 stopped installing the bundled firmware next to a current
`linux-firmware-cirrus`. The copies were byte-identical to the package's, but
as uncompressed files they shadowed it, and their per-amp `-l2uN.wmfw` names,
which upstream never uses, are looked up before the package's generic
`104315e4.wmfw`. A newer Cirrus firmware would never have loaded. Updating
removes copies identical to the bundled ones and leaves any other file alone.

`audio-fix` 3.1 uses a small B9406CAA-only `snd-soc-sof-sdw` DKMS overlay only
on kernels that still need it. It discards only an RT722 that the SoundWire
core has positively marked `UNATTACHED`; real RT722 hardware and every other
model are untouched. The permanent DMI fix is already accepted upstream as
[`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8).
Install inspects every installed kernel module rather than guessing from its
version, skips DKMS on kernels containing the upstream quirk (Linux 7.3+), and
removes the overlay automatically once every installed kernel has it. The
quirk carries no `Cc: stable`, so no 7.2.y or 6.18.y release has it yet and
7.2 kernels still need the overlay. 3.1.1 fixes the overlay build on 7.2.y
kernels whose `soc_sdw_utils` API gained the `dev, ctx` arguments through a
stable backport (3.0.0 silently failed to rebuild there and audio fell back to
*Dummy Output*); it probes the header instead of trusting the version, and no
longer forces `LLVM=1` on GCC-built kernels.

| File | Path | What it does |
|---|---|---|
| `cs35l56-…-l2u{0,1}.{bin,wmfw}` | `/lib/firmware/cirrus/` | Per-OEM tuning + ROM 3.4.4→3.13.4 patch. **Only on `linux-firmware-cirrus < 20260519`**; newer packages ship identical files, and the bundled copies are removed there. |
| `sof-soundwire.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | Upstream `alsa-ucm-conf` master: fixes the `SpeakerCodec` regex to keep the `-spk` suffix. Pinned via `NoExtract` so a partial upgrade can't revert it (both only on `alsa-ucm-conf < 1.2.16`). |
| `cs35l56+cs42l43-spk.conf`, `cs42l43-spk+cs35l56.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | The Speaker device for the combined codec — routes playback to `hw:,2` and the CS35L56 + CS42L43 amps. |
| `cs42l43-spk+cs35l56-init.conf` | `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/` | Combined codec init (control remap + LED attach). `module.sh` symlinks `cs35l56+cs42l43-spk` → this so both kernel names resolve. |
| `52-disable-bt-sco-offload.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Disables the dead `SSP2-BT` offload PCM so its probe stops spamming the log on pre-7.1 kernels (inert on 7.1+, where the PCM no longer exists). Bluetooth audio (A2DP/HFP) still works via the PipeWire software path. |
| `dkms/asus-expertbook-sof-sdw-3.0.2/` | `/usr/src/` + `/lib/modules/*/updates/dkms/` | Compatibility overlay for released kernels lacking upstream commit `90af3209742d`; not built where the in-kernel DMI quirk is detected, and DKMS never builds it for 7.3+. Upgrades compile the new overlay for every kernel first and take the old one off a kernel only once its replacement exists. |

> The **F1 speaker-mute LED** needs `asus-wmi`'s `platform::mute` (WMI device
> `0x0004001C`), which lands in Linux 7.4. Until then only `platform::micmute`
> exists; the kernel's `audio-micmute` trigger drives it.

</details>

### 3. [`wifi-fix`](wifi-fix/) — BE211: disable broken EHT, diagnose C106 warnings

<details><summary><b>The bug</b> — Wi-Fi 7 / EHT is broken on BE211</summary>

The core problem is **802.11be (EHT / Wi-Fi 7) itself** on the Intel BE211
(`8086:e440`) under `iwlwifi`/`iwlmld`: the EHT RX path can collapse to
**MCS0 / NSS1** and MLO sessions tear down, so the "Wi-Fi 7" link is slower and
flakier than plain Wi-Fi 6 on this laptop.

```
$ journalctl -k -b | grep -c "missed beacons exceeds"
7228    # possible with Linux 7.2 C106 even on a strong, connected HE link
```

</details>

<details><summary><b>The fix</b> — disable broken EHT and report the separate C106 warning flood honestly</summary>

Drop the broken 802.11be layer so the radio runs as Wi-Fi 6 (HE). Same approach
Omarchy ships; verified at ~2.1 Gbit/s over 160 MHz HE here:

| File | Path | What it does |
|---|---|---|
| `iwlwifi-disable-eht.conf` | `/etc/modprobe.d/` | `options iwlwifi disable_11be=Y` — disables EHT / Wi-Fi 7; the link falls back to stable Wi-Fi 6 / HE. |

Linux 7.2 additionally loads C106 firmware, and the driver can log thousands of
`missed beacons ... but receiving data` warnings while the link remains strong,
fast and connected. On the reference machine the bursts followed a single
access point every 30–37 minutes and vanished on others, which points at an AP
pausing its beacons (off-channel scanning, for example) more than at C106. Status
shows the loaded firmware and count; it does not silence the warning or rewrite
packaged firmware. Version 2.1 retires the old global ASPM-performance,
power-scheme and offload tunables because they did not stop the warnings and
were broader than the demonstrated bug. Linux 7.3 loads C107 and 7.4 is set to
take C108; EHT stays off until a retest there shows the RX collapse is gone.

This is a deliberate **Wi-Fi 7 → Wi-Fi 6** downgrade. Normal power management,
offloads and `iwlwifi.bt_coex_active=Y` are retained, so Bluetooth coexistence
continues to work.

</details>

### 4. [`display-fix`](display-fix/) — PSR1 self-refresh and working brightness

<details><summary><b>The bug</b> — Panel Replay washes out HDR and leaves stale frames; PSR2 paints garbage</summary>

The Samsung Display Corp panel in this laptop reports IEEE OUI `00:aa:01` in
DPCD register 0x300 and supports Panel Replay Selective Update (Early
Transport), which is the self-refresh mode Linux 7.2's `xe` picks by default
on Panther Lake. In that mode the panel comes up visibly desaturated after
every HDR-enabling modeset (KWin's HDR toggle, a fresh login with HDR on), and
stale content lingers on screen after updates. The colors come back as soon as
anything streams frames with the SDPs again (a KWin color-accuracy toggle, a
write to `i915_edp_psr_debug`), so the panel appears to miss the new
BT.2020/PQ signaling once Panel Replay stops the stream on a static desktop.
Dropping only Early Transport keeps the washed out colors and slows cursor
motion to ~20 fps, so Panel Replay itself is at fault.

Disabling Panel Replay alone (`xe.enable_panel_replay=0`, or the first
version of the [`upstream-patches/0001`](upstream-patches/) quirk) is worse: `xe` falls back
to PSR2 selective update over the panel's DSC link, and every screen update
paints red/green speckle garbage, goes black, then parks on garbage or the
correct image at random. The most plausible cause is that the driver gates
PSR2 + DSC on platform generation only, never on sink capability, while this
panel advertises DSC selective update for Panel Replay alone. Disabling only
selective fetch (`xe.enable_psr2_sel_fetch=0`) is not an option either: it
keeps Panel Replay without selective update, which on Panther Lake freezes
the panel on the boot console text until a VT switch repaints it.

Linux 7.0/7.1 also wedged the display engine outright, and 7.2 has not
retired that signature under the Panel Replay default:

```
xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state
xe 0000:00:02.0: [drm] *ERROR* [CRTC:151:pipe A] DSB 0 timed out waiting for idle
kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver
```

On 7.0/7.1 a selective-fetch DSB deadlock under heavy compositing (a screen
capture was enough) took the whole kernel down silently. A 7.2.0 boot with
only the backlight parameter still logged `DSB 0 poll error`, `CPU pipe A
FIFO underrun` and `Timed out waiting PSR idle state`, with corruption
visible on screen
([issue #7](https://github.com/burakgon/asus-expertbook-linux/issues/7)).
The `mismatch in vsc dp vsc sdp` error and `intel_modeset_verify.c`
WARN that 7.2 logs on every HDR modeset are a separate false positive: the
driver's VSC SDP readout rejects the revision 7 packet it emits itself for
Panel Replay with colorimetry, so the state checker compares against zeros.
The upstream fix, "drm/i915/dp: Handle VSC SDP revision 7 in unpack"
(`fd2e337ba66f`), is in drm-intel-next and should reach Linux 7.4.

</details>

<details><summary><b>The fix</b> — pin self-refresh to PSR1 and force the VESA DPCD backlight</summary>

| File | Path | What it does |
|---|---|---|
| `xe-dpcd-backlight.conf` | `/etc/modprobe.d/` | `enable_dpcd_backlight=2 enable_panel_replay=0 enable_psr=1` for a late xe module load. |
| `limine-display.conf` | `/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf` | Adds `xe.enable_dpcd_backlight=2 xe.enable_panel_replay=0 xe.enable_psr=1` to every Limine kernel entry. Value `2` forces the VESA AUX/DPCD interface when sysfs brightness otherwise changes without changing panel luminance. |

PSR1 (full-frame self-refresh without selective update) passes everything
testable on this panel: vivid colors across HDR off/on toggles, a smooth
cursor, none of the stale-content artifacts, and self-refresh still saves
power on a static screen. Both PSR parameters are needed. `xe.enable_psr=1`
alone leaves Panel Replay on, since Panel Replay bypasses the PSR2 validity
check that parameter feeds into, and `xe.enable_panel_replay=0` alone lands in
the PSR2 + DSC garbage described above. To try it without a reboot, write
`0x43` to `/sys/kernel/debug/dri/*/i915_edp_psr_debug` as root (`0x40`
disables Panel Replay, `0x03` forces PSR1; never write `0x03` on its own,
which keeps Panel Replay and drops only selective update, the combination
that freezes the boot) and confirm `PSR mode: PSR1 enabled` in
`/sys/kernel/debug/dri/*/eDP-1/i915_psr_status`.

The older `xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0` pair that
some owners already boot with lands on PSR1 as well: Panther Lake has no PSR2
hardware tracking, so without selective fetch the driver drops PSR2 and runs
PSR1. `xe.enable_psr=1` says the same thing directly, and `./patch.sh status
display-fix` accepts either pair.

Version 1.4 replaces 1.3's "keep the Linux 7.2 defaults" stance. With only
the backlight parameter on the cmdline, owners reported PSR idle timeouts, DSB
poll errors, FIFO underruns and on-screen corruption on 7.2.0, panel flicker
and VRR smearing on 7.2.4, and washed-out HDR with stale frames on 7.2.2
([issue #7](https://github.com/burakgon/asus-expertbook-linux/issues/7)).
Install removes the old `xe-disable-psr.conf`, which turned self-refresh off
entirely. It no longer touches Omarchy's own
`/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf`: that file sets
only `xe.enable_panel_replay=0`, which agrees with PSR1. Version 1.3 archived
it; 1.4 puts it back. Only a hand-edited copy that sets `xe.enable_psr` or
`xe.enable_panel_replay` to something else is archived, because it sorts
after this module's drop-in and would override it. `./patch.sh status
display-fix` warns when Panel Replay stays on, when `xe.enable_panel_replay=0`
appears without a PSR2 disable, when `xe.enable_psr=0` turns self-refresh off,
and when the panel's debugfs status reports anything but PSR1 (with VRR
active the driver keeps PSR off, so the debugfs line reads `disabled`).

GRUB users put the same three parameters on `GRUB_CMDLINE_LINUX_DEFAULT` in
`/etc/default/grub` and run `grub-mkconfig -o /boot/grub/grub.cfg`; the
modprobe.d half of the module still applies.

</details>

<details><summary><b>Known issues</b> — what PSR1 does not cover (Linux 7.2, Panther Lake)</summary>

- `Selective fetch area calculation failed in pipe A` once per boot is an
  informational fallback to a full-frame update. It is harmless and goes away
  with PSR1, which does not use selective fetch.
- **Stock 7.2.y kernels** (Arch, Omarchy) carry only half of the fix for the
  trace-less hard freeze from display page tables in stolen memory
  (drm/xe #7513). The second half, `0687ec06f51b` ("Do not allocate into
  stolen for new framebuffers"), is in 7.3; CachyOS kernels carry it since
  7.2.1 ([CachyOS#986](https://github.com/CachyOS/linux-cachyos/issues/986)).
- `DSB 0 timed out` / `flip_done timed out` with VRR's short vblank is fixed by
  `b201029ca695` ("Ensure a non-zero safe window from PTL onwards") in 7.3,
  with no stable tag.
- Fullscreen switches on a Panther Lake Samsung OLED under KDE have been
  reported to cause plane faults and DSB poll errors on 7.2.7 (drm/xe #9385);
  `KWIN_DRM_NO_DIRECT_SCANOUT=1` avoids them.
- With PSR1 active, KWin may be unable to turn VRR on at runtime, because the
  change needs a full modeset (drm/xe #9359).
- A 5K Apple Studio Display on this CPU can stay black after a cold boot even
  though the link trains; a physical replug brings it up (drm/xe #9153, open).
- Poweroff or reboot can hang in `nhi_pci_remove` on 7.2.y with a
  Thunderbolt/USB4 dock driving DisplayPort monitors; reproduced on a B9406CAA
  with a CalDigit TS5. Fixes are queued for 7.3 with `Cc: stable`
  ([CachyOS#1047](https://github.com/CachyOS/linux-cachyos/issues/1047)).
  Unplug the dock before shutting down, or boot the 6.18 LTS kernel.

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

### 6. [`intel-perf-fix`](intel-perf-fix/) — Panther Lake thermal policy

<details><summary><b>The bug</b> — the OEM's thermal tables go unused</summary>

Panther Lake is an "adaptive" thermal platform: the firmware carries the OEM's
own thermal tables (Intel DTT: PL1/PL2 limits, passive trip points, a
power-slider condition). The kernel's int340x drivers expose the sensors and
limits, but nothing in the kernel runs that policy.

Scheduling is not the gap it looks like. This 16-core CPU has no SMT, so the
kernel places work by core capacity ("Hybrid CPU capacity scaling enabled",
P 1024 / E 701 / LP-E 625) instead of ITMT.

</details>

<details><summary><b>The fix</b> — thermald by default, intel-lpmd opt-in</summary>

| Package | Source (Arch; Debian/Ubuntu) | Service | Effect |
|---|---|---|---|
| `thermald` | `extra`; `main` | `thermald.service` | Runs the OEM's adaptive thermal tables (supported on Panther Lake since 2.5.9). Can lower limits if a BIOS table is bad; since 2.5.12 it restores them when stopped, so an A/B test is easy. |
| `intel-lpmd` | `extra` / `cachyos`; Ubuntu `universe`, not in Debian | `intel_lpmd.service` | **Opt-in** (`sudo INTEL_PERF_LPMD=1 ./patch.sh install intel-perf-fix`). In low-power mode it confines system/user/machine.slice to the four LP-E CPUs, forces `intel_pstate` to active mode and moves the SoC power slider. |

Package and service calls go through `lib/distro.sh`, so the hook also runs on
apt systems. On Debian and Ubuntu only the thermald half is useful for now:
Debian has no `intel-lpmd` package, and Ubuntu 24.04's 0.0.3 (February 2024)
predates Panther Lake and exits within milliseconds of starting (verified on
Pop!_OS 24.04). With `INTEL_PERF_LPMD=1` the module warns when the enabled unit
is not running and points at its journal; the unit stays enabled so a package
upgrade that adds support starts it.

Version 1.2 stopped enabling `intel-lpmd` by default. Intel labels 0.1.1 (the
CachyOS build) a test release not meant for distributions, and upstream main
no longer changes cpusets by default. A public Panther Lake A/B test (XPS 16,
battery, balanced) found no significant idle-power gain and roughly doubled
app launch time with it; apps started while confined also size their thread
pools to four CPUs. Updating from 1.1 disables the service unless
`INTEL_PERF_LPMD=1` is set. The earlier "parks idle work on a single LP-E
core" and "≈2–2.5 W idle" claims were never measured on this laptop.

`power-profiles-daemon` stays in charge of profiles. `thermald` reads its
slider state; `intel-lpmd`, when enabled, touches the same `intel_pstate` and
SoC-slider settings, so the three are not fully independent layers.

This module ships **no payload files** — it's purely package install + service
enable in the post-install hook. The patcher tracks it the same way it
tracks file-based modules (versioned, idempotent, status-checked). Package and
service calls go through [`lib/distro.sh`](lib/distro.sh), so the same hook
runs unchanged on pacman and apt systems.

</details>

### 7. [`keyboard-backlight-auto`](keyboard-backlight-auto/) — *(optional)* ambient-light keyboard backlight

Version 1.3.0 closes disconnected input devices and discovers replacements
every five seconds. This fixes a busy loop after a virtual keyboard disappears
(for example, a ydotool restart). Updates restart the running daemon, and status
reports its CPU average. See [system health checks](docs/system-health.md) for
runtime verification and optional IR-camera troubleshooting.

> KDE PowerDevil reads the ambient light sensor for **screen** brightness only —
> there is no keyboard equivalent. Without this module the backlight only ever
> changes when you press the Fn keys, and `systemd-backlight` restores a dark
> keyboard at every boot.

<details><summary><b>The curve</b> — Microsoft's Windows 11 default, and it is deliberately not monotonic</summary>

The bucketized **ambient light response (ALR) curve** is Microsoft's documented
Windows 11 default for *Keyboard Backlight Autobrightness*, reproduced verbatim
down to the registry string format:

| Bucket | Min lux | Max lux | Percentage | Level here (max 3) |
|---:|---:|---:|---:|---:|
| 1 | 0 | 6 | 35% | 1 |
| 2 | 5 | 14 | 52% | 2 |
| 3 | 12 | 32 | 70% | 2 |
| 4 | 30 | 45 | 88% | 3 |
| 5 | 40 | 100 | **100%** | 3 |
| 6 | 95 | 110 | 88% | 3 |
| 7 | 105 | 160 | 70% | 2 |
| 8 | 155 | 205 | 52% | 2 |
| 9 | 200 | 300 | 0% | 0 |

The keyboard is *dimmest-but-on* in the dark, brightest between 40 and 100 lux,
and off above 200–300 lux. That shape is the counter-intuitive part and it is
intentional: in true darkness a keyboard at full power is glare against a
dark-adapted eye, and in a bright room the keycap legends are already readable
by ambient light, where backlighting only washes out their contrast.

Apple's *Computer light adjustment* patents (US 7,839,379 and family) describe
the simpler inverse relationship instead. We follow Microsoft's because it is an
exact, numeric, currently-maintained table rather than a prose description.

</details>

<details><summary><b>The rest of the machinery</b> — smoothing, hysteresis, manual override, lid</summary>

| Piece | Where it comes from |
|---|---|
| **Smoothing** | GNOME's `gsd-power-manager.c`: `alpha = 1 / (1 + τ/dt)`, `acc = alpha·reading + (1−alpha)·acc`, with `τ = 1/(2π × 0.1 Hz)` ≈ **1.6 s**. Driven by the measured `dt`, so a missed sample doesn't distort it. |
| **Hysteresis** | Free, from Microsoft's **overlapping** buckets (1 is 0–6 lux, 2 is 5–14, …). The daemon stays in the bucket it is in while the reading remains inside that bucket's range, so a reading hovering at 5.5 lux cannot flap between 35% and 52%. |
| **Manual override** | Microsoft's lookup table: an Fn keypress creates a window around the current reading (at 120 lux, `40:150:0.60:0.60` gives 48–192 lux) and autobrightness resumes once the reading leaves it. Detected via `brightness_hw_changed` — see below. |
| **Lid** | Ours. Lid shut → backlight forced to 0, and any active override is dropped so the curve, not a level chosen in another room, decides on reopen. State comes from the `Lid Switch` evdev device, with `/proc/acpi/button/lid/*/state` as the initial reading and fallback. |

Finding the keypress took some digging. The Fn backlight keys emit **no input
event at all** — verified on 2026-09-02 by listening on all fifteen
`/dev/input/event*` devices while they were pressed, which captured nothing but
touchpad traffic. The `Asus WMI hotkeys` device advertises
`KEY_KBDILLUMUP`/`KEY_KBDILLUMDOWN` only because `asus-nb-wmi`'s sparse keymap
declares them.

The OS is not blind to them though. The kernel reports EC-initiated changes
through the LED class's **`brightness_hw_changed`** attribute (`POLLPRI`) —
which is how UPower notices and relays
`BrightnessChangedWithSource(level, "internal")`, and in turn what raises KDE's
on-screen display. That attribute carries the **real level**, unlike the plain
`brightness` node stuck at `0`, so the daemon both detects the press and learns
what you chose:

```
EC set level 3/3 | manual override active for 0.0-18.5 lux (reading 9.2)
EC set level 0/3 | manual override active for 0.0-18.4 lux (reading 9.2)
```

One adaptation to the spec remains: Microsoft's host holds a *specific*
percentage during an override, while here it means **"stop writing"** — the
level you picked is yours until the ambient reading leaves the window. A value
matching what the daemon itself last wrote is treated as its own change echoing
back, so it never starts a spurious override. To stop the daemon touching the
backlight at all, set `enabled = no` or
`sudo systemctl stop kbd-backlight-auto`.

Watch it decide without letting it touch the backlight:

```sh
sudo kbd-backlight-auto --probe -v
```

```
17.3 lux | bucket 3 (12-32 lux, 70%) | would set level 2/3
20.4 lux | bucket 3 (12-32 lux, 70%) | level 2/3 (unchanged)
```

Everything is tunable in `/etc/kbd-backlight-auto.conf`, including the curve and
the override table in Microsoft's own string format. The one knob worth knowing
about is `calibration`: the curve's thresholds are **absolute lux**, so a
mis-scaled sensor puts the keyboard in the wrong bucket.

</details>

### 8. [`keyboard-backlight-fix`](keyboard-backlight-fix/) — *(superseded)* the v1.x `asusd` workaround, and why it was wrong

> **This module skips its own install.** On BIOS `B9406CAA.312` with mainline
> `asus-wmi`, keyboard brightness already reaches the EC without it. It is kept
> for older firmware and for the record.

<details><summary><b>The correction</b> — the write path was never broken; the read path is</summary>

Versions 1.x claimed the BIOS's `SLKB` ACPI method clamped OS-initiated
brightness writes to zero, and shipped `asusd` to translate them into the
OEM-tested `0x100..0x103` range. Re-measured on **2026-09-02** with `asusctl`
**not installed**, `/etc/asusd` absent and `asusd` inactive:

| Path | Result |
|---|---|
| `echo 0/1/2/3 > /sys/class/leds/asus::kbd_backlight/brightness` | **Works** — the keyboard visibly steps through all four levels |
| KDE PowerDevil slider | **Works**, for the same reason |
| `cat …/brightness`, UPower `GetBrightness`, `brightnessctl` | **Always `0`** — all three read the same attribute |

The `SLKB` disassembly was accurate; the claim about which branch Linux reaches
was not. Mainline `asus-wmi` never writes the bare `0..3` range that the buggy
branch clamps:

```c
static void kbd_led_update(struct asus_wmi *asus)
{
	int ctrl_param = 0;

	scoped_guard(spinlock_irqsave, &asus_ref.lock)
		ctrl_param = 0x80 | (asus->kbd_led_wk & 0x7F);
	asus_wmi_set_devstate(ASUS_WMI_DEVID_KBD_BACKLIGHT, ctrl_param, NULL);
}
```

`0x80 | level` lands in `0x80..0x83` — `SLKB`'s **second** branch, the one v1.x
itself documented as working. `asusd`'s range translation had nothing to fix.

The real defect is `kbd_led_read()`: the firmware's query returns nothing usable,
so the level always masks down to `0`. `asusd` does not fix that either — it is a
firmware read path, not a range problem.

The defect is in the *query* path only, though. The LED's sibling attribute
`brightness_hw_changed` **does** report the real level whenever the EC changes it
— that is how UPower relays `BrightnessChangedWithSource(…, "internal")` and how
KDE's on-screen display appears on an Fn keypress. It is a notification, not a
queryable state, so `cat brightness` stays broken; `keyboard-backlight-auto` uses
it to stay in sync with a hand-set level. The visible cost is that
`systemd-backlight@leds:asus::kbd_backlight` saves `0` at every shutdown and
restores a dark keyboard at every boot; `keyboard-backlight-auto` is ordered
`After=` it and overrides it within a second.

The v1.x status check was a **false negative by construction** — it wrote a level
and read it back, and the read is always `0`, so it reported `FAILED` on a
perfectly working backlight. That check is gone.

What stays unknown is whether software control was genuinely broken on BIOS
`B9406CAA.304`, the firmware v1.x was written against; the reference machine has
since moved to `312` and 304 is no longer testable. What can be said is that the
*mechanism* v1.x blamed cannot have been the cause. That uncertainty is why the
module is kept rather than deleted:

```sh
sudo KBF_FORCE=1 ./patch.sh install keyboard-backlight-fix
```

</details>

### 9. [`camera-firmware`](camera-firmware/) — verified 3009 update without Windows

The ASUS camera updater is a Windows EXE, but its payload is a signed UEFI
capsule. This module reads the camera ESRT GUID locally and compares it only to
the verified **3009 / 10.1.2.3009** baseline (`raw 479569`). It performs no
online latest-version lookup.

If the installed value is older or missing, `./patch.sh install
camera-firmware` displays both versions and asks before doing anything. After
confirmation it uses a matching local EXE or downloads the single fixed ASUS
3009 artifact, verifies the pinned EXE and capsule SHA-256 values, and stages
the capsule with `fwupd`. The Windows program is never executed. A reboot with
AC connected applies it; current/equal/newer firmware is never reflashed.

See [`camera-firmware/README.md`](camera-firmware/README.md) for the hashes,
ESRT GUID and local-package paths.

### 10. [`ish-firmware`](ish-firmware/) — the ambient light sensor's missing firmware

The ambient light sensor sits behind the Intel Integrated Sensor Hub
(`00:12.0`, `8086:e445`), which only runs after the kernel uploads an
OEM-signed image at boot. Before the generic `ish_ptl.bin` the loader asks for
per-OEM names built from CRC-32s of the DMI strings, such as
`intel/ish/ish_ptl_<crc32(sys_vendor)>_<crc32(product_name)>.bin` — a rule
that reproduces linux-firmware's Lenovo/Dell entries exactly — but linux-firmware
ships no ASUS image, and this board rejects the generic one
(`ISH loader: cmd 2 failed 10`). Result: no `als` device, ever.

Same approach as `camera-firmware`: the module downloads (or uses a verified
local copy of) ASUS's fixed **Intel Sensor Hub V5.8.62.0** package, checks the
pinned SHA-256 of the EXE and of the embedded
`AsusSign_ishS_SI_B9406CAA_5.8.1.7783.bin`, installs it as
`/lib/firmware/updates/intel/ish/ish_ptl_59b8d9f2_6f5619d0.bin` (vendor +
product name, which every Panther Lake kernel from 6.14 on tries) and reloads
`intel_ish_ipc`. A udev rule keeps the ISH out of runtime suspend, which
`intel_ish_ipc` does not support. Nothing is flashed and nothing ASUS-owned is
redistributed. Install it before `keyboard-backlight-auto`.

See [`ish-firmware/README.md`](ish-firmware/README.md) for the evidence,
hashes and the naming rule.

### 11. [`power-profile-bridge`](power-profile-bridge/) — Power Save that actually saves

Panther Lake registers two platform-profile handlers here, Intel's
`SoC Power Slider` (`low-power balanced performance`) and `asus-wmi`
(`quiet balanced performance`). The legacy `/sys/firmware/acpi/platform_profile`
that power-profiles-daemon drives lists only the choices both share, so its
Power Save writes `balanced`: the slider never reaches `low-power` and the fans
never reach `quiet` ([asusctl#387](https://github.com/OpenGamingCollective/asusctl/issues/387)).
Going from Performance straight to Power Save is worse: power-profiles-daemon
writes `balanced` to emulate power-saver, then reads its own write back and
switches itself to Balanced. A small root service follows the daemon's
`ActiveProfile` over D-Bus and writes each handler's own
`/sys/class/platform-profile/*/profile`, and a drop-in starts the daemon with
`--block-driver=platform_profile`, so it keeps CPU EPP and the bridge alone
writes platform profiles. Details in
[`power-profile-bridge/README.md`](power-profile-bridge/README.md).

### 12. [`touchpad-haptics`](touchpad-haptics/) — *(optional)* click force and haptic strength

The pad is a Windows Precision Touchpad pressure pad with two standard HID
feature reports: Button Press Threshold (report 8, 1–3) and Haptic Intensity
(report 9, 0–100). A small CLI sends validated `SET_FEATURE` requests after
matching the pad's HID ID and exact report descriptor; a udev rule gives the
logged-in user access and restores saved values at boot, because the firmware
forgets them at power-off. Details in
[`touchpad-haptics/README.md`](touchpad-haptics/README.md).

### 13. [`hdr-fix`](hdr-fix/) — *(optional)* HDR toggle for the internal OLED

The panel's EDID declares HDR (PQ, max 1600 cd/m², BT.2020 RGB) inside a
DisplayID 2.0 extension. libdisplay-info 0.3.0, which KWin uses, does not look
there; 0.4.0 does but changes the soname. The module builds 0.3.0 from its
pinned release tarball with the seven upstream DisplayID 2.0 commits, three
upstream hardening fixes, and two fixes of our own for an out-of-bounds read
and a leak those upstream commits still carry (found by fuzzing under
AddressSanitizer; both drafted for upstream, not yet sent). It keeps the `.so.3` ABI (all
packaged symbols exported, upstream tests 64/64 also under ASan), installs the
library under `/usr/local/lib/asus-expertbook-hdr` and puts that directory in
`/etc/ld.so.conf.d`. No pacman file is touched. It only builds against package
releases known to be plain upstream 0.3.0, and a pacman hook removes the
override whenever the `libdisplay-info` package changes. Details in
[`hdr-fix/README.md`](hdr-fix/README.md).

### 14. [`mute-led-fix`](mute-led-fix/) — F1/F4 mute indicators

Linux 7.2 does not expose the speaker mute LED. This module registers
`platform::mute` through the exported ASUS WMI API, with the kernel
`audio-mute` trigger, and stops building once 7.4 provides that LED itself.
An optional per-user service can follow speaker mute, microphone mute, or
both; it leaves an LED alone while a kernel trigger owns it. Hardware
confirmation so far is Omarchy on BIOS B9406CAA.312 and Linux 7.2.3.
Suspend/resume and non-Omarchy desktops have not been retested with this
revision. See [`mute-led-fix/README.md`](mute-led-fix/README.md).

```sh
./patch.sh install mute-led-fix
```

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
├── camera-firmware/            # verified ASUS 3009 capsule staging
├── display-fix/  …
├── hdr-fix/                    # libdisplay-info 0.3.0 + DisplayID 2.0 backport patches
├── intel-perf-fix/  …
├── ish-firmware/               # verified ASUS Sensor Hub image staging
├── keyboard-backlight-auto/  …
├── keyboard-backlight-fix/  …
├── mute-led-fix/  …             # F1/F4 LEDs; speaker and mic sync are separate
├── power-profile-bridge/  …
├── touchpad-fix/  …
├── touchpad-haptics/  …
├── webcam-ai-fix/  …
├── wifi-fix/  …
├── upstream-patches/           # accepted/pending upstream patches + tracker drafts
│   └── 0001, 0003–0006.patch, stable request, issue drafts
├── lib/
│   └── distro.sh               # package manager / initramfs / bootloader / services
├── docs/                       # the GitHub Pages site
└── scripts/
    └── check-hardware.sh       # one-shot compatibility check
```

A module's manifest declares files (source → destination), optional custom
install/state hooks, post-install/runtime checks, and a version. The
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
| `./patch.sh diff [module…]` | Show what would change in the module's shipped files before installing. Packages, DKMS builds, firmware downloads and files written by install hooks are not part of the diff. |
| `./patch.sh install-all` | Install every discoverable module; camera firmware is only offered when older and still asks for confirmation. |
| `./patch.sh update-all` | Re-install only modules that aren't `up to date`. |
| `./patch.sh uninstall-all` | Tear down installed configuration modules; applied device firmware is not downgraded. |

## Kernel & distro compatibility

- **Linux 6.18+** for the haptic-touchpad kernel parser, the new `iwlmld`
  Wi-Fi 7 op-mode, the `xe` driver Panther Lake bringup, and the
  `cs35l56` driver. Anything older won't even probe most of this
  hardware.
- **Tested on:** the audio DKMS overlay compiles against
  `linux-cachyos-lts 6.18.52`, `linux-cachyos 7.2.8`, and
  `linux-cachyos-rc 7.3.0-rc4` (where the upstream quirk makes it unnecessary).
  Matching kernel headers are required; the normal Arch/CachyOS DKMS hooks
  rebuild it before boot images on upgrades. Compiling is not the same as a
  working card on 6.18: that kernel lacks the default function-topology machine
  fallback and the `ptl_cs42l43_agg_l3_cs35l56_l2` match that arrived in 6.19,
  so speaker audio on 6.18 LTS is unverified.
- **Distros:** Arch and Arch derivatives (CachyOS, EndeavourOS, Manjaro)
  all use the same `/etc/udev/hwdb.d`, `/etc/libinput`,
  `/etc/modprobe.d`, `/etc/wireplumber/wireplumber.conf.d` paths the
  modules write to.
- **Debian / Ubuntu / Pop!_OS:** partial, and being added one module at a
  time. [`lib/distro.sh`](lib/distro.sh) abstracts the package manager,
  kernel-header discovery, initramfs regeneration, kernel-cmdline backend and
  service enablement, so a module written against those helpers runs on both
  families. Ported so far:

  | Module | Debian/Ubuntu | Note |
  |---|---|---|
  | `touchpad-fix` | works | config files only; needs `libinput-tools` for the `libinput quirks validate` check |
  | `wifi-fix` | works | config files only |
  | `keyboard-backlight-auto` | works | config files plus a python3 daemon and its unit; no package manager involved |
  | `intel-perf-fix` | partial | `thermald` works (Ubuntu 24.04's `2.5.6-2ubuntu0.24.04.3` carries the Panther Lake backport). `intel-lpmd` is absent on Debian and, on Ubuntu 24.04, too old (0.0.3) to recognise Panther Lake — it installs and exits at once. Both cases are reported, not hidden |
  | `display-fix` | not yet | needs the cmdline backend wired into the module |
  | `audio-fix` | not yet | Measured on Pop!_OS 24.04 against an earlier version. Fixed since: `dkms.conf` no longer forces `LLVM=1` (3.1.1), and overlay 3.0.2 is limited to 6.x–7.2 kernels and keeps going when one kernel fails to build. Still open: `audio_require_build_tools` installs `clang`, which GCC-built Debian kernels do not need; the bundled UCM files declare Syntax 7, which needs alsa-lib >= 1.2.12 (Ubuntu 24.04 ships 1.2.11), so installing them breaks UCM for the whole `sof-soundwire` family; the `NoExtract` pin maps to `dpkg-divert`; firmware ownership checks use `pacman -Qo` |
  | `camera-firmware` | not yet | needs `fwupd`, `jq`, `7z`, `curl` mapped to Debian names |
  | `ish-firmware` | untested | installs files only, but needs `7z` and `curl` and checks ownership with `pacman -Qo` |
  | `touchpad-haptics` | untested | files, a python3 CLI, a udev rule and a oneshot unit; no package manager involved |
  | `power-profile-bridge` | untested | needs a power-profiles-daemon with `--block-driver` (0.30 has it) |
  | `hdr-fix` | not planned | refuses anything but the exact Arch/CachyOS libdisplay-info 0.3.0 packages it was built against |
  | `webcam-ai-fix`, `keyboard-backlight-fix` | not planned | depend on AUR-only packages (`obs-backgroundremoval`, `asusctl`); `keyboard-backlight-fix` is superseded by `keyboard-backlight-auto` anyway |

  Tracking issue: [#4](https://github.com/burakgon/asus-expertbook-linux/issues/4).
- **Bootloader assumption (display-fix):** `limine` via
  `limine-mkinitcpio-hook`, where `/etc/limine-entry-tool.d/` drop-ins are the
  source of truth. If you use systemd-boot or GRUB, the module's
  cmdline-injection hook needs swapping; the modprobe.d half still works.
  `lib/distro.sh` already implements all three backends
  (`cmdline_backend` → `limine` | `kernelstub` | `grub`); the module itself
  has not been migrated onto them yet.

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

### Platform helpers

Hooks run in a subshell that inherits everything `patch.sh` defines, including
[`lib/distro.sh`](lib/distro.sh). Use these instead of calling `pacman`,
`mkinitcpio`, `limine-update` or `systemctl` directly, and the module works on
Arch and Debian families alike:

| Helper | Does |
|---|---|
| `distro_family` | `arch` \| `debian` \| `unknown` (reads `ID` *and* `ID_LIKE`) |
| `pkg_manager` | `pacman` \| `apt` \| `none` |
| `pkg_install <pkg>…` | `pacman -S --needed --noconfirm` / `apt-get install -y` |
| `pkg_version <pkg>` | installed version, empty when absent |
| `pkg_installed` / `pkg_available` | is it installed / known to the repos |
| `pkg_atleast <pkg> <ver>` | version comparison, for gating bundled payloads |
| `pkg_remove_hint <pkg>…` | the removal command to print for the user |
| `kernel_list` | installed kernel releases, one per line |
| `kernel_headers_present [kver]` / `kernel_headers_install [kver]` | DKMS prerequisites |
| `initramfs_regen [reason]` | `limine-mkinitcpio` → `mkinitcpio -P` → `update-initramfs` → `dracut` |
| `cmdline_backend` | `limine` \| `kernelstub` \| `grub` \| `none` |
| `cmdline_add` / `cmdline_remove <param>…` | idempotent kernel-parameter edits |
| `cmdline_active` / `cmdline_active_value` / `cmdline_configured` | what is live vs. staged |
| `svc_unit <candidate>…` | resolve a unit name that differs between distros |
| `svc_enable_now` / `svc_disable_now` / `svc_is_active` / `svc_exists` | systemd |

Testing overrides — never set these in normal use: `GRUB_FILE`,
`KERNELSTUB_FILE`, `LIMINE_DROPIN_DIR`, `CMDLINE_BACKEND`.

Sibling-model contributions for `1043:15d4` and `1043:15f4` ExpertBook
Ultra variants are very welcome — open a PR with your subsystem ID's
firmware blobs (if cs35l56 is the same chip family) and any DMI tweaks
needed.

## Upstream submissions

The [`upstream-patches/`](upstream-patches/) folder separates accepted,
pending and retired work:

| # | Tree | Replaces |
|---|---|---|
| `0001` | Linux display (`intel_quirks.c`) | `display-fix`: pins this laptop to PSR1 through the existing Panel Replay (subsystem + sink OUI) and PSR2 (PCI ID) quirk tables. Not sent: tested through the equivalent module parameters, still needs one built-kernel test |
| former `0002` | Linux sound | Removed: B9406CAA is not a sidecar-amplifier design |
| `0003` | libinput | `touchpad-fix`'s override: marks `093A:4F05` as a pressure pad (`INPUT_PROP_PRESSUREPAD`), as upstream did for `4811`. Not sent: needs an on-device test |
| `0004` | Linux SoundWire | **Accepted** as upstream commit `90af3209742d` (Linux 7.3); retained for backports, stable request for 7.2.y drafted |
| `0005` | power-profiles-daemon | `power-profile-bridge`'s drop-in: stops an emulated power-saver from switching itself back to balanced. Not sent; its new test fails on main and the suite passes with it |
| `0006` | Linux platform/x86 (`asus-wmi`) | Keyboard backlight read-back quirk from [#12](https://github.com/burakgon/asus-expertbook-linux/pull/12): the level stops reading as 0. Not sent |
| drafts | drm/xe, libdisplay-info, Arch | The drm/xe issue for `0001`, a libdisplay-info report for the DisplayID v2 overread fixed in `hdr-fix`, and a request for Arch to ship libdisplay-info 0.4.0 |

See the tracking notes for current applicability against `torvalds/linux` /
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
upstream `linux-firmware`. The camera capsule is strictly B9406CAA-only. The
`touchpad-fix`, `wifi-fix`,
`display-fix`, `intel-perf-fix`, `webcam-ai-fix`,
`keyboard-backlight-auto` and
`keyboard-backlight-fix` modules are hardware-agnostic or match by
family-level identifiers and apply more broadly.

PRs adding `module.sh` entries for sibling models are welcome.

</details>

<details><summary><b>Does the fingerprint reader work?</b></summary>

Yes. The FocalTech FT9349 (`2808:a97a`) is supported by upstream
`libfprint 1.94.100` and later. Install the normal `libfprint` + `fprintd`
packages, then enroll with `fprintd-enroll`. No out-of-tree patch is needed on
current Arch/CachyOS.

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
before Linux 7.4, because until then this laptop exposes no speaker-mute LED
device to Linux — there's nothing for the UCM `SetLED` hook to bind to.
Linux 7.4's `asus-wmi` adds `platform::mute` (WMI device `0x0004001C`) with an
audio-mute trigger. A bridge for older kernels is under review in
[#16](https://github.com/burakgon/asus-expertbook-linux/pull/16). It's a
missing-device limitation, not a profile issue.

</details>

<details><summary><b>Why not just upstream all of this and skip the repo?</b></summary>

That's the goal — see [`upstream-patches/`](upstream-patches/). The UCM and
firmware are already released, and the B9406CAA ghost-RT722 kernel quirk landed
in Linus' tree as `90af3209742d` after Linux 7.2. `audio-fix` detects backports
from the installed module itself, so its DKMS compatibility overlay disappears
as soon as all installed kernels contain the upstream fix. The camera module
remains a safe bridge for ASUS's Windows-packaged firmware capsule.

</details>

<details><summary><b>How do I test changes before installing?</b></summary>

```sh
./patch.sh diff <module>          # before/after for the files in the module's MODULE_FILES
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
