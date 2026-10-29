# ASUS ExpertBook Ultra (B9406CAA) — speaker / headphone audio fix on Linux

Out of the box on Linux 6.18+, the internal speakers are silent (and the F1
mute LED is stuck "on"). Five independent problems stack up:

1. **CS35L56 firmware missing.** The Cirrus **CS35L56** speaker amplifiers boot
   in `FIRMWARE_MISSING` state. They each need a per-OEM `.bin` (tuning) **and**
   a `.wmfw` (firmware patch upgrading chip ROM `3.4.4` → `3.13.4`).
   `linux-firmware-cirrus >= 20260519` now ships these upstream for this
   laptop's PCI subsystem ID `1043:15e4`; on anything older they're missing.

2. **Combined speaker-codec UCM gap.** The card reports a *combined* speaker
   codec — `spk:cs35l56+cs42l43-spk` (or two `spk:` tags on older kernels:
   2× CS35L56 + the CS42L43 speaker path). Stock `alsa-ucm-conf 1.2.15.x` has
   **no UCM** for that combination **and** its `SpeakerCodec` regex drops the
   trailing `-spk`, so `alsaucm` fails to open
   (`codecs/cs35l56+cs42l43/init.conf: -2`). WirePlumber then falls back to an
   unrouted `stereo-fallback` profile that plays to the **Jack** PCM (device 0),
   not the **Speaker** PCM (device 2) — silent speakers, even though
   `aplay -D plughw:0,2` works. **`alsa-ucm-conf 1.2.16` ships the fix upstream**
   (the exact files below, verbatim).

3. **Ghost RT722 prevents ALSA card registration.** B9406CAA firmware describes
   a Realtek RT722 on SoundWire link 3 even though the peripheral is not fitted.
   Current kernels leave it `UNATTACHED` but still build a second
   `SDW3-Playback-SimpleJack` beside the real CS42L43. The duplicate sysfs link
   aborts `sof_sdw` with `-EEXIST` / error `-12`, leaving PipeWire with only
   **Dummy Output**.

4. **Dead SSP2-BT topology node (kernels before 7.1).** The generic SOF
   topology declares an unused `SSP2-BT` hardware-offload PCM with no firmware
   blob; WirePlumber's probe of it spams the kernel log
   (`SSP2-BT.capture: failed to prepare`, ~40% of all kernel errors at boot).
   The 7.1+ function topologies no longer expose that PCM.

5. **`sof-firmware` missing.** SOF firmware and topologies are a separate Arch
   package. Without it no card appears even with every fix above
   (`SOF firmware and/or topology file not found ... sof-ptl.ri`). Install pulls
   it in when it is missing.

## What this module does

Installs the proper **HiFi UCM** profile (not a profile hack): named ports,
headphone-jack **auto-switching**, working volume, and the mic-mute LED. The
result is a real `HiFi__Speaker__sink` on PCM device 2 with all 6 speakers and
the CS35L56 DSP running calibrated firmware. On released kernels that lack the
permanent SoundWire DMI quirk, a B9406CAA-only DKMS overlay removes only the
exact RT722 device when the core reports it as `UNATTACHED`. Version 3.1 checks
each installed kernel module for upstream commit `90af3209742d`, builds the
overlay only where needed, and removes it once every kernel contains the quirk.

> **The UCM half is upstream as of `alsa-ucm-conf 1.2.16`.** On a system with
> `alsa-ucm-conf >= 1.2.16` this module installs **no** files under
> `/usr/share/alsa/ucm2` and adds **no** `NoExtract` pin — the UCM already
> belongs to the package, and dropping our own copies in would only create a
> pacman file-conflict on the next `alsa-ucm-conf` upgrade. There it is
> effectively **adaptive DKMS + firmware + SSP2-BT-noise-fix only**. The bundled UCM files are
> kept purely as a fallback for systems still on `alsa-ucm-conf < 1.2.16`, where
> `module_post_install` drops them in and pins `sof-soundwire.conf`.

## Files

### Always installed

| Source | Install path | Purpose |
|---|---|---|
| `cs35l56-…-l2u0.bin` / `.wmfw` | `/lib/firmware/cirrus/` | Per-OEM tuning + ROM `3.4.4`→`3.13.4` patch, left amp. **Only on `linux-firmware-cirrus < 20260519`** (see below). |
| `cs35l56-…-l2u1.bin` / `.wmfw` | `/lib/firmware/cirrus/` | Same, right amp. |
| `52-disable-bt-sco-offload.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Disables the dead `SSP2-BT` offload PCM so its probe stops spamming the log (pre-7.1 kernels; inert on 7.1+). A2DP/HFP Bluetooth still works via the PipeWire software path. |
| `dkms/asus-expertbook-sof-sdw-3.0.3/` | `/usr/src/asus-expertbook-sof-sdw-3.0.3/` + `/lib/modules/*/updates/dkms/` | Board-scoped compatibility filter, built only for 6.19–7.2 kernels lacking upstream commit `90af3209742d` (never by DKMS for 7.3+ or before 6.19); on 7.2.11 it also restores the CS35L56 feedback DAI. Install also regenerates initramfs images. |

### Installed only on `alsa-ucm-conf < 1.2.16` (otherwise the package provides them)

| Source | Install path | Purpose |
|---|---|---|
| `sof-soundwire.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | Fixes the `SpeakerCodec` regex to keep the `-spk` suffix. Pinned via `NoExtract` so a partial upgrade can't revert it — until the upgrade crosses 1.2.16, where the pin is dropped automatically. |
| `cs35l56+cs42l43-spk.conf`, `cs42l43-spk+cs35l56.conf` | `/usr/share/alsa/ucm2/sof-soundwire/` | The Speaker device for the combined codec — routes playback to `hw:,2` and the CS35L56 + CS42L43 amps. |
| `cs42l43-spk+cs35l56-init.conf` | `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf` | Combined codec init (control remap + LED attach). A `cs35l56+cs42l43-spk` symlink is created so both kernel codec names resolve. |

The `.bin` / `.wmfw` blobs come verbatim from upstream
[linux-firmware](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/cirrus)
(the `.wmfw` is the generic `CS35L56_Rev3.13.4.wmfw` renamed into the per-OEM
filename the driver looks for). The UCM files come verbatim from upstream
[alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) master — the same
content that shipped in release 1.2.16.

## Install

From the project root:

```sh
./patch.sh install audio-fix
sudo reboot
```

After reboot, verify:

```sh
sudo dmesg | grep cs35l56
# expect: "Firmware: ... v3.13.4" and "Tuning PID:" for both amps,
#         no "FIRMWARE_MISSING", no "Can't read tuning IDs".
# No "Calibration applied": this unit has no CirrusSmartAmpCalibrationData
# EFI variable, so the kernel skips per-unit calibration silently.

pactl list cards | grep "Active Profile"
# expect: Active Profile: HiFi
```

If the Speaker isn't already the default sink, set it once (WirePlumber
persists it):

```sh
pactl set-default-sink alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__Speaker__sink
```

`./patch.sh status audio-fix` also reports the cs35l56 firmware state and the
active card profile.

### "Dummy Output" / no ALSA card

The userspace files in `audio-fix` can route and tune a card only after the
kernel has registered it. If `wpctl status` shows only **Dummy Output**, check:

```sh
cat /proc/asound/cards
journalctl -k -b | grep -Ei 'sof|soundwire|cs35|cs42|snd'
```

An empty card list together with `SDW3-Playback-SimpleJack`, `-EEXIST`, or
`sof_sdw ... error -12` in the kernel log is the known phantom-RT722 failure.
The duplicate SoundWire link aborts the `sof_sdw` probe before firmware, UCM,
PipeWire, or WirePlumber can participate. Install `audio-fix` 3.3.0 and reboot
once. Its DKMS module is the packaged compatibility workaround;
`./patch.sh status audio-fix` verifies the registration and selected module
path for the running kernel.

On **Linux 7.2.11** the card can also fail with `CODEC DAI cs35l56-ot25 not
registered` even though the overlay is installed
([#28](https://github.com/burakgon/asus-expertbook-linux/issues/28)). Stable
7.2.11 took "ASoC: sdw_utils: Switch CS35L56/57/62/63 to use OT25 DAI" without
its prerequisite "ASoC: cs35l56: Add DAI for SDCA OT25 stream", so the amps
never register the DAI the feedback link names. Overlay 3.0.3 (`audio-fix`
3.3.0) points that link back at `cs35l56-sdw1c`, as 7.2.10 did, on 7.2.11
only; 7.2.12 has both halves. `./patch.sh status audio-fix` recognizes the
message.

If audio disappears right after a kernel update, check whether DKMS actually
rebuilt the overlay: `dkms status asus-expertbook-sof-sdw` must say
`installed` for the running kernel. `added` means the build failed and the
stock driver is back; the reason is in
`/var/lib/dkms/asus-expertbook-sof-sdw/*/build/make.log`. This is what broke
overlay 3.0.0 on Linux 7.2.8, whose stable update backported the 7.3
`asoc_sdw_parse_sdw_endpoints(dev, ctx, ...)` signature; 3.0.1 detects that
signature from the kernel headers. 3.0.2 adds a kernel range
(`BUILD_EXCLUSIVE_KERNEL`, 6.x to 7.2): 3.0.1 let DKMS autoinstall build it for
7.3+ kernels too, where it would replace the kernel's newer `sof_sdw` with this
7.2-level copy although 7.3 has the quirk itself. 3.0.3 narrows the range to
6.19–7.2: the 6.18 LTS cannot build it since 6.18.55 backported the 7.3 API,
and before 6.19 there is no card to fix anyway (see Known limitations).
`audio-fix` 3.3.0 skips such kernels with a warning instead of failing the
install.

Upgrading the overlay compiles the new version for every kernel first. A
kernel's older overlay is taken off (`dkms uninstall`, which keeps its build)
only once its new build exists, and reinstalled from that build if installing
the new one fails; a kernel whose build fails, or that has no headers, keeps
the older overlay, and the install then stops and names it. Older overlays and
their sources are deleted only when no kernel still runs one.
Kernels that contain the upstream quirk lose any overlay build left for them.
An overlay change always comes with a new version: a registered version whose
source differs from the checkout is refused rather than rebuilt in place. The
source in `/usr/src` is owned by root, older overlays' sources included
(earlier installs left them owned by the user who cloned the repository,
although root compiles them into the kernel).

The permanent fix was accepted as upstream commit
[`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8).
The exact patch is retained in
[`upstream-patches/0004`](../upstream-patches/0004-soundwire-dmi-quirks-Disable-ghost-rt722-on-ASUS-Exp.patch)
for stable/distro backports. It first ships in Linux 7.3 (since 7.3-rc1) and is
still absent from 7.2.8; the installer detects the actual marker in
`soundwire_intel` instead of assuming a version.

## Uninstall

```sh
./patch.sh uninstall audio-fix
sudo reboot
```

On `alsa-ucm-conf >= 1.2.16` uninstall removes the DKMS overlay, firmware
fallbacks and SSP2-BT drop-in. The HiFi UCM is left in place because it belongs
to the package, not to this module. Initramfs images are regenerated with the
stock kernel driver restored.

## Known limitations

- **No speakers before Linux 6.19, the 6.18 LTS included.** The machine
  driver match for this laptop's codecs (`ptl_cs42l43_agg_l3_cs35l56_l2`) and
  the default function-topology fallback arrived in 6.19; 6.18.55's
  `snd-soc-acpi-intel-match` still lacks it, so no card comes up with or
  without the overlay. Install skips those kernels with a warning, and
  `./patch.sh status audio-fix` says so when one is running.
- **F1 speaker-mute LED stays in its EC default state before Linux 7.4.**
  `asus-wmi` gains `platform::mute` (WMI device `0x0004001C`, audio-mute
  trigger) in 7.4. Until then only `platform::micmute` exists, driven by the
  kernel's `audio-micmute` trigger; [`mute-led-fix`](../mute-led-fix/) adds
  the speaker LED on older kernels.
- **The bundled cs35l56 blobs are a fallback only.** On
  `linux-firmware-cirrus >= 20260519` the package ships the `1043:15e4` tuning
  (per-amp `-l2uN.bin` plus the generic Rev 3.13.4 `.wmfw`), byte-identical to
  the bundled files. Up to 3.1.1 this module installed its uncompressed copies
  anyway. They shadowed the package, and their per-amp `-l2uN.wmfw` names,
  which upstream never uses, are looked up before the generic `.wmfw`, so a
  newer Cirrus firmware would never have loaded. 3.2.0 installs them only on
  older packages and removes copies identical to the bundled ones.

## Upstream tracking

All three core pieces are now upstream; the kernel quirk first ships in
Linux 7.3:

- **UCM:** shipped in `alsa-ucm-conf 1.2.16` (combined `cs42l43-spk+cs35l56`
  codec dir + `sof-soundwire` `-spk` regex + the speaker confs). ✅
- **Firmware:** shipped in `linux-firmware-cirrus >= 20260519` for `1043:15e4`. ✅
- **Ghost RT722:** accepted in Linus' tree as `90af3209742d`, present since
  7.3-rc1; not in 7.2.y or 6.18.y stable as of 7.2.8 / 6.18.54, because the
  commit carries no `Cc: stable`. A stable request citing the precedent
  `6d49beec658f` (the GX651AX ghost quirk, which did reach 7.2.8) is drafted in
  [`upstream-patches/`](../upstream-patches/). ✅

The module keeps DKMS only for installed kernels that do not contain that DMI
entry. It also keeps the `52-disable-bt-sco-offload.conf` drop-in until that
unused PCM is removed from the SOF topology upstream.
