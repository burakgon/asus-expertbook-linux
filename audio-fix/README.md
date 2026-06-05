# ASUS ExpertBook Ultra (B9406CAA) — speaker / headphone audio fix on Linux

Out of the box on Linux 6.18+, the internal speakers are silent (and the F1
mute LED is stuck "on"). Three independent problems stack up:

1. **CS35L56 firmware missing.** The Cirrus **CS35L56** speaker amplifiers boot
   in `FIRMWARE_MISSING` state. They each need a per-OEM `.bin` (tuning) **and**
   a `.wmfw` (firmware patch upgrading chip ROM `3.4.4` → `3.13.4`).
   `linux-firmware-cirrus >= 20260519` now ships these upstream for this
   laptop's PCI subsystem ID `1043:15e4`; on anything older they're missing.

2. **Combined sidecar-amp UCM gap.** The card reports a *combined* speaker
   codec — `spk:cs35l56+cs42l43-spk` (or two `spk:` tags on older kernels:
   2× CS35L56 + the CS42L43 sidecar amp). Stock `alsa-ucm-conf 1.2.15.x` has
   **no UCM** for that combination **and** its `SpeakerCodec` regex drops the
   trailing `-spk`, so `alsaucm` fails to open
   (`codecs/cs35l56+cs42l43/init.conf: -2`). WirePlumber then falls back to an
   unrouted `stereo-fallback` profile that plays to the **Jack** PCM (device 0),
   not the **Speaker** PCM (device 2) — silent speakers, even though
   `aplay -D plughw:0,2` works. **`alsa-ucm-conf 1.2.16` ships the fix upstream**
   (the exact files below, verbatim).

3. **Dead SSP2-BT topology node.** The generic SOF topology declares an unused
   `SSP2-BT` hardware-offload PCM with no firmware blob; WirePlumber's probe of
   it spams the kernel log (`SSP2-BT.capture: failed to prepare`, ~40% of all
   kernel errors at boot).

## What this module does

Installs the proper **HiFi UCM** profile (not a profile hack): named ports,
headphone-jack **auto-switching**, working volume, and the mic-mute LED. The
result is a real `HiFi__Speaker__sink` on PCM device 2 with all 6 speakers and
the CS35L56 DSP running calibrated firmware.

> **The UCM half is upstream as of `alsa-ucm-conf 1.2.16`.** On a system with
> `alsa-ucm-conf >= 1.2.16` this module installs **no** files under
> `/usr/share/alsa/ucm2` and adds **no** `NoExtract` pin — the UCM already
> belongs to the package, and dropping our own copies in would only create a
> pacman file-conflict on the next `alsa-ucm-conf` upgrade. There it is
> effectively **firmware + SSP2-BT-noise-fix only**. The bundled UCM files are
> kept purely as a fallback for systems still on `alsa-ucm-conf < 1.2.16`, where
> `module_post_install` drops them in and pins `sof-soundwire.conf`.

## Files

### Always installed

| Source | Install path | Purpose |
|---|---|---|
| `cs35l56-…-l2u0.bin` / `.wmfw` | `/lib/firmware/cirrus/` | Per-OEM tuning + ROM `3.4.4`→`3.13.4` patch, left amp. **Fallback** for `linux-firmware-cirrus < 20260519`. |
| `cs35l56-…-l2u1.bin` / `.wmfw` | `/lib/firmware/cirrus/` | Same, right amp. |
| `52-disable-bt-sco-offload.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Disables the dead `SSP2-BT` offload PCM so its probe stops spamming the log. A2DP/HFP Bluetooth still works via the PipeWire software path. |

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
# expect: "Calibration applied", no "FIRMWARE_MISSING", no "Can't read tuning IDs"

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

## Uninstall

```sh
./patch.sh uninstall audio-fix
sudo reboot
```

On `alsa-ucm-conf >= 1.2.16` the uninstall only removes the firmware blobs and
the SSP2-BT drop-in — the HiFi UCM is left in place because it belongs to the
package, not to this module.

## Known limitations

- **F1 speaker-mute LED stays in its EC default state.** This laptop exposes no
  speaker-mute LED device to Linux — only `platform::micmute`, which the HiFi
  UCM *does* drive. There is nothing to bind the speaker-mute key to.
- **The bundled cs35l56 blobs are a fallback.** On `linux-firmware-cirrus >=
  20260519` the package already ships the `1043:15e4` tuning, so the bundled
  copies are redundant (same filenames, same content).

## Upstream tracking

The two big pieces are now upstream:

- **UCM:** shipped in `alsa-ucm-conf 1.2.16` (combined `cs42l43-spk+cs35l56`
  codec dir + `sof-soundwire` `-spk` regex + the speaker confs). ✅
- **Firmware:** shipped in `linux-firmware-cirrus >= 20260519` for `1043:15e4`. ✅

On a fully up-to-date system the only thing this module still adds is the
`52-disable-bt-sco-offload.conf` WirePlumber drop-in that silences the dead
`SSP2-BT` topology node. Once that unused PCM is dropped from the SOF topology
upstream, the module becomes fully redundant and can be uninstalled.
