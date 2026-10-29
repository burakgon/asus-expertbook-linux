# ASUS ExpertBook Ultra (B9406CAA) — touchpad fix on Linux

PixArt I2C-HID haptic touchpad `093A:4F05` (ACPI ID `ASCP1D80`) does not move
the cursor out of the box. The pad's HID report descriptor gives Tip Pressure
no Logical Maximum of its own, so it inherits the Y field's 2601, and the
kernel reports that as the `ABS_MT_PRESSURE` maximum. Real presses sit far
below it, so libinput discards every motion as
`kernel bug: Touch jump detected and discarded`.

Confirmed reproducible on:

- ASUS ExpertBook Ultra (B9406CAA, 2026, Panther Lake)
- Kernel: `linux-cachyos 7.0.11`
- libinput 1.31.3, KDE Plasma on Wayland (CachyOS)

## Files

| File | Install path | What it does |
|---|---|---|
| `61-pixart-4f05-pressure-fix.hwdb` | `/etc/udev/hwdb.d/` | Clamps `ABS_PRESSURE` and `ABS_MT_PRESSURE` axes to 0:100 so libinput's pressure heuristics see sane values. |
| `99-asus-expertbook-pixart-4f05.quirks` | managed block in `/etc/libinput/local-overrides.quirks` | Tells libinput to ignore both pressure axes entirely (pattern borrowed from the shipped Asus UX302LA quirk). |

libinput reads admin overrides only from `/etc/libinput/local-overrides.quirks`;
any other `*.quirks` file in `/etc/libinput` is ignored. That file is shared
with every other override on the machine, so since 1.2.0 the module writes a
marked block into it instead of replacing it. Install drops earlier B9406
touchpad sections (the 1.1.x copy and Omarchy-derived ones) and keeps every
other section; uninstall removes only the block. The rewritten file must pass
`libinput quirks validate` before it replaces the old one, which is kept as
`local-overrides.quirks.asus-expertbook-linux.bak`; a broken file would make
libinput drop every quirk on the machine, so the `libinput quirks` tool
(package `libinput-tools`; on older Arch builds it ships in `libinput` itself) is required. If
the begin/end markers do not pair up (edited by hand), install and uninstall
stop without touching the file. A lock keeps two runs from overwriting each
other's edit.

The libinput quirk is the load-bearing fix and is sufficient on its own
(verified on the reference machine: the hwdb clamp is **not** installed, the
kernel still reports `ABS_MT_PRESSURE` max 2601, yet there are zero Touch-jumps
and the cursor tracks fine). The hwdb is optional belt-and-suspenders — install
it too if you want libinput's pressure heuristics to also see sane 0:100 values,
but it is not required.

## Install

```sh
./patch.sh install touchpad-fix
sudo reboot
```

By hand, append the section to the one file libinput reads (a copy under any
other name in `/etc/libinput` is silently ignored):

```sh
sudo cp 61-pixart-4f05-pressure-fix.hwdb /etc/udev/hwdb.d/
cat 99-asus-expertbook-pixart-4f05.quirks | sudo tee -a /etc/libinput/local-overrides.quirks
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
./patch.sh uninstall touchpad-fix
sudo reboot
```

By hand: delete `/etc/udev/hwdb.d/61-pixart-4f05-pressure-fix.hwdb`, remove the
`[ASUS ExpertBook Ultra B9406 Touchpad]` section from
`/etc/libinput/local-overrides.quirks`, run `sudo systemd-hwdb update` and
reboot.

## Diagnosis trail (for upstream bug reports)

- `evtest /dev/input/event9` shows clean kernel events with smooth
  `ABS_MT_POSITION_X/Y` deltas (no jumps).
- Real `ABS_MT_PRESSURE` values observed: 0..1000 (peak around 1000).
- Kernel-reported `ABS_MT_PRESSURE` max: 2601 (= `ABS_Y` max — wrong).
- libinput log lines while broken:
  `Libinput: event9 - ASCP1D80:00 093A:4F05 Touchpad: kernel bug: Touch jump detected and discarded.`

Root cause: the pad's own HID report descriptor. Tip Pressure declares no
Logical Maximum, so under HID's global-item rules it inherits the value last
set, the Y field's 2601. It is not a kernel parser bug.

The sister pad `093A:4811` showed the same symptoms and was fixed upstream in
libinput 1.32 with `AttrInputProp=+INPUT_PROP_PRESSUREPAD`
([issue 1318](https://gitlab.freedesktop.org/libinput/libinput/-/issues/1318),
[MR 1504](https://gitlab.freedesktop.org/libinput/libinput/-/merge_requests/1504)).
The kernel sets that property on its own only when a pad reports Button
Type 1; this one does not. A `4F05` section next to `4811` in
`30-vendor-pixart.quirks` is the upstream fix; see
[`upstream-patches/`](../upstream-patches/). Attach
`sudo libinput record -o expertbook.yml /dev/input/event9` to the merge
request.

## Notes

- Workaround is userspace-only; survives kernel and libinput upgrades.
- Once a proper `093A:4F05` quirk lands in
  `/usr/share/libinput/30-vendor-pixart.quirks` and/or a kernel HID parser
  fix lands, both files here can be removed.
