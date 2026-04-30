# ASUS ExpertBook Ultra (B9406CAA) — touchpad fix on Linux

PixArt I2C-HID haptic touchpad `093A:4F05` (ACPI ID `ASCP1D80`) does not work
on Linux kernels 6.18+ (haptic-touchpad parser landed via `CONFIG_HID_HAPTIC`).
The kernel reports a bogus `ABS_MT_PRESSURE` max (2601, identical to the
Y-axis max), and libinput discards every motion as a `kernel bug: Touch jump
detected and discarded`, so the cursor never moves.

Confirmed reproducible on:

- ASUS ExpertBook Ultra (B9406CAA, 2026, Panther Lake)
- Kernels: `linux-cachyos 7.0.2`, `linux-cachyos-rc 7.1.rc1`
- libinput 1.31.1, KDE Plasma on Wayland (CachyOS)

## Files

| File | Install path | What it does |
|---|---|---|
| `61-pixart-4f05-pressure-fix.hwdb` | `/etc/udev/hwdb.d/` | Clamps `ABS_PRESSURE` and `ABS_MT_PRESSURE` axes to 0:100 so libinput's pressure heuristics see sane values. |
| `99-asus-expertbook-pixart-4f05.quirks` | `/etc/libinput/` | Tells libinput to ignore both pressure axes entirely (pattern borrowed from the shipped Asus UX302LA quirk). |

Either file alone helps. Both together give the most reliable behaviour.

## Install

```sh
sudo cp 61-pixart-4f05-pressure-fix.hwdb       /etc/udev/hwdb.d/
sudo cp 99-asus-expertbook-pixart-4f05.quirks  /etc/libinput/
sudo systemd-hwdb update
sudo reboot
```

After reboot, verify the libinput quirk is loaded:

```sh
sudo libinput quirks list /dev/input/event9
# expect: AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
```

And that the hwdb override took:

```sh
sudo evtest /dev/input/event9 | grep -A 3 'ABS_MT_PRESSURE'
# expect: Max  100
```

## Uninstall

```sh
sudo rm /etc/udev/hwdb.d/61-pixart-4f05-pressure-fix.hwdb
sudo rm /etc/libinput/99-asus-expertbook-pixart-4f05.quirks
sudo systemd-hwdb update
sudo reboot
```

## Diagnosis trail (for upstream bug reports)

- `evtest /dev/input/event9` shows clean kernel events with smooth
  `ABS_MT_POSITION_X/Y` deltas (no jumps).
- Real `ABS_MT_PRESSURE` values observed: 0..1000 (peak around 1000).
- Kernel-reported `ABS_MT_PRESSURE` max: 2601 (= `ABS_Y` max — wrong).
- libinput log lines while broken:
  `Libinput: event9 - ASCP1D80:00 093A:4F05 Touchpad: kernel bug: Touch jump detected and discarded.`

Likely root cause: the `CONFIG_HID_HAPTIC` parser in `hid-multitouch`
mis-applies the Y-axis logical max to the pressure axis when parsing this
device's HID descriptor. Worth filing at:

- libinput: <https://gitlab.freedesktop.org/libinput/libinput/-/issues>
  (attach `sudo libinput record -o expertbook.yml /dev/input/event9`)
- linux-input: <https://bugzilla.kernel.org> under Drivers / Input Devices

## Notes

- Workaround is userspace-only; survives kernel and libinput upgrades.
- Once a proper `093A:4F05` quirk lands in
  `/usr/share/libinput/30-vendor-pixart.quirks` and/or a kernel HID parser
  fix lands, both files here can be removed.
