# ASUS ExpertBook Ultra (B9406CAA) — speaker audio fix on Linux

Out of the box, internal speakers are silent on Linux 6.18+ (and the F1 mute
LED is stuck "on") because:

1. The Cirrus **CS35L56** speaker amplifiers boot in `FIRMWARE_MISSING` state.
   `linux-firmware-cirrus` (2026‑03 and 2026‑04 packages) does not ship the
   OEM tuning files for this laptop's PCI subsystem ID `1043:15e4`. Both
   amps need a per‑OEM `.bin` (tuning) **and** a `.wmfw` (firmware patch
   upgrading chip ROM `3.4.4` → `3.13.4`).

2. ALSA UCM falls back to an unrouted `stereo-fallback` profile because the
   codec directory `cs42l43-spk+cs35l56/` is missing under
   `/usr/share/alsa/ucm2/codecs/`. The card declares
   `spk:cs42l43-spk+cs35l56` in `alsa.components`, so libucm tries to load
   `codecs/cs42l43-spk+cs35l56/init.conf` and gives up when it isn't there.

3. Even after firmware loads, WirePlumber sticks with the
   `stereo-fallback` profile. None of its sinks reach the speaker amps.

Confirmed reproducible on:

- ASUS ExpertBook Ultra (B9406CAA, 2026, Panther Lake, PCI subsystem `1043:15e4`)
- Kernels: `linux-cachyos 7.0.2`, `linux-cachyos-rc 7.1.rc1`
- `linux-firmware-cirrus 1:20260309-1` (cachyos), `20260410-1` (core)
- `alsa-ucm-conf 1.2.15.3-1`
- WirePlumber `0.5.14` / PipeWire `1.6.4`

## Files

| Source | Install path | Purpose |
|---|---|---|
| `cs35l56-b0-dsp1-misc-104315e4-l2u0.bin` | `/lib/firmware/cirrus/` | Per-OEM tuning blob, link 2 unit 0 (left amp) |
| `cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw` | `/lib/firmware/cirrus/` | Firmware patch (ROM 3.4.4 → 3.13.4), left amp |
| `cs35l56-b0-dsp1-misc-104315e4-l2u1.bin` | `/lib/firmware/cirrus/` | Per-OEM tuning, link 2 unit 1 (right amp) |
| `cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw` | `/lib/firmware/cirrus/` | Firmware patch, right amp |
| `cs42l43-spk+cs35l56-init.conf` | `/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf` | Combined codec init (control remap + LED attach) |
| `51-asus-expertbook-pro-audio.conf` | `/etc/wireplumber/wireplumber.conf.d/` | Pin card to `pro-audio` so Speaker sink is reachable |

The `.bin` files come from the upstream `linux-firmware` repository
([cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.bin](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/cirrus)).
The `.wmfw` is the generic `cs35l56/CS35L56_Rev3.13.4.wmfw` from the same repo,
renamed into the per‑OEM filename pattern the cs35l56 driver looks for.
The dmesg banner shows the file was actually built by Cirrus for ASUS
B9406CAA (`Misc: ...\\Cirrus Logic\\...\\ASUS\\B9406CAA\\...`).

## Install

From the project root:

```sh
./patch.sh install audio-fix
sudo reboot
```

After reboot, verify with:

```sh
sudo dmesg | grep cs35l56
# expect: "Calibration applied", no "FIRMWARE_MISSING", no "Can't read tuning IDs"

pactl list cards | grep "Active Profile"
# expect: Active Profile: pro-audio
```

If the Speaker isn't already the default sink, set it once
(WirePlumber persists it):

```sh
pactl set-default-sink alsa_output.pci-0000_00_1f.3-platform-sof_sdw.pro-output-2
```

## Uninstall

```sh
./patch.sh uninstall audio-fix
sudo reboot
```

## Known limitations

- **F1 mute LED stays in EC firmware default state.** The UCM `SetLED`
  binding in `cs42l43-spk+cs35l56-init.conf` only takes effect when a
  HiFi UCM profile is active for the card; with `pro-audio` we bypass
  UCM. A proper HiFi profile for this codec combination has to land
  upstream in `alsa-ucm-conf` first.
- **Pro Audio exposes 8 raw PCM sinks.** Other than Speaker
  (`pro-output-2`), Jack (`pro-output-0`), HDMI (`pro-output-5/6/7`),
  Bluetooth (`pro-output-20`), and Deepbuffer variants are also
  visible. They share the card so most users will only ever pick
  Speaker as default.
- **Bluetooth audio capture errors** (`SSP2-BT.capture: failed to prepare`)
  in dmesg are unrelated to this fix and predate it. They originate in
  SOF's topology, not the speaker amps.

## Upstream tracking

Once upstream linux‑firmware adds a `cs35l56-b0-dsp1-misc-104315e4*.wmfw`
file and `alsa-ucm-conf` ships a real `cs42l43-spk+cs35l56` codec dir
(and a sof‑soundwire matcher that selects HiFi for it), this entire
module becomes redundant — uninstall and remove.
