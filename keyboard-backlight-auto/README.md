# keyboard-backlight-auto

**Optional.** Drive the keyboard backlight from the ambient light sensor, the
way Windows and macOS do on this class of hardware. Without it the backlight
only ever changes when you press the Fn keys or move the KDE slider — KDE
PowerDevil reads the ambient light sensor for *screen* brightness only and has
no keyboard equivalent.

## The rules are borrowed, not invented

Two shipping implementations supply everything here.

### The curve — Microsoft

The bucketized **ambient light response (ALR) curve** and the manual-override
lookup table are Microsoft's documented Windows 11 defaults for *Keyboard
Backlight Autobrightness*, reproduced verbatim — down to the registry string
format, so the values below are directly comparable with
`HKLM\SOFTWARE\Microsoft\Lighting\Backlight\BacklightAutobrightnessBucketMapping`.

| Bucket | Min lux | Max lux | Percentage | Level on this machine (max 3) |
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

**The curve is deliberately not monotonic**, which is the part that surprises
people: the keyboard is *dimmest-but-on* in the dark, brightest in the
40–100 lux range, and switches off entirely above 200–300 lux. The reasoning
is the same one that governs display brightness — in true darkness a keyboard
at full power is glare against a dark-adapted eye, and in a bright room the
keycap legends are already readable by ambient light, where backlighting only
washes out their contrast.

Apple's *Computer light adjustment* patents (US 7,839,379 and family) describe
the simpler inverse relationship instead — brighter as the room gets darker,
off above roughly 5–10 lux. We follow Microsoft's because it is an exact,
numeric, currently-maintained table rather than a prose description, and
because a 4-step LED needs concrete thresholds.

### Smoothing — GNOME

Raw sensor readings jitter, so they go through the same first-order low-pass
filter `gnome-settings-daemon` uses in `plugins/power/gsd-power-manager.c`
(`iio_proxy_changed`):

```c
alpha = 1.0f / (1.0f + (GSD_AMBIENT_TIME_CONSTANT / (current_time - last_time)));
accumulator = (alpha * brightness) + (1.0 - alpha) * accumulator;
```

with `GSD_AMBIENT_TIME_CONSTANT = 1 / (2π × GSD_AMBIENT_BANDWIDTH_HZ)` and
`GSD_AMBIENT_BANDWIDTH_HZ = 0.1`, i.e. a time constant of about **1.6 s**.
Because the filter is driven by the measured `dt` rather than a fixed step, a
missed sample doesn't distort it.

### Hysteresis — free, from the overlaps

No extra machinery is needed. Microsoft's buckets **overlap** (bucket 1 is
0–6 lux, bucket 2 is 5–14, and so on), and the daemon stays in the bucket it
is already in for as long as the reading remains inside that bucket's range.
A reading hovering at 5.5 lux therefore cannot flap between 35% and 52% — it
keeps whichever it entered from.

## What this module adds on top

### Manual override (Fn keys)

Straight from Microsoft's spec: pressing a backlight key creates a temporary
override window around the current reading, and autobrightness resumes once
the ambient level leaves it. At 120 lux the table entry `40:150:0.60:0.60`
gives `120 × (1 − 0.6)` to `120 × (1 + 0.6)`, i.e. **48–192 lux**.

**Finding the keypress took some digging.** The Fn backlight keys emit **no
input event at all** — verified on 2026-09-02 by listening on all fifteen
`/dev/input/event*` devices while the keys were pressed, which captured nothing
but touchpad traffic. The `Asus WMI hotkeys` device advertises `KEY_KBDILLUMUP`
and `KEY_KBDILLUMDOWN` in its capability bitmap only because `asus-nb-wmi`'s
sparse keymap declares them.

But the OS is *not* blind to them. The kernel reports EC-initiated changes
through the LED class's **`brightness_hw_changed`** attribute (`POLLPRI`), which
is exactly how UPower notices — it relays
`BrightnessChangedWithSource(level, "internal")`, and that is what raises KDE's
on-screen display when you press the key. Observed on the system bus while the
keys were pressed:

```
member=BrightnessChangedWithSource   int32 1   string "internal"
member=BrightnessChangedWithSource   int32 2   string "internal"
member=BrightnessChangedWithSource   int32 3   string "internal"
```

So the daemon watches `brightness_hw_changed`. That attribute carries the
**real level**, unlike the plain `brightness` node that is stuck at `0` — which
means the daemon both detects the press and learns what you chose:

```
EC set level 3/3 | manual override active for 0.0-18.5 lux (reading 9.2)
EC set level 0/3 | manual override active for 0.0-18.4 lux (reading 9.2)
```

One adaptation to Microsoft's spec remains: their host holds a *specific*
percentage during an override, while here the override means **"stop writing"**
— the level you picked is yours to keep until the ambient reading leaves the
window. A value matching what the daemon itself last wrote is treated as its own
change echoing back, not a user action, so it never starts a spurious override.

To stop the daemon touching the backlight at all, set `enabled = no` or
`sudo systemctl stop kbd-backlight-auto`.

### Lid handling

Not part of either upstream spec; this is ours. With the lid shut the keyboard
isn't visible, so the backlight is forced to 0. Closing the lid also drops any
active manual override, so the curve — not a level you chose in a different
room — takes over when the lid comes back up.

Lid state comes from the `Lid Switch` evdev device, with
`/proc/acpi/button/lid/*/state` as the initial reading and as a fallback for
firmware that never fires the switch.

## Machine-specific notes

**The LED's read-back is broken — but only the `brightness` node.** Writes to
`/sys/class/leds/asus::kbd_backlight/brightness` reach the EC across the whole
`0..3` range, yet reading that node back always returns `0`: the firmware's
query path is dead, and `asus-wmi`'s `kbd_led_read()` masks whatever it gets
with `0x7F`. The daemon therefore never reads it; it tracks what it last wrote.

The sibling attribute **`brightness_hw_changed` does report real levels**, but
only for EC-initiated changes — it is a notification of what the hardware just
did, not a queryable current state. That is enough to keep the daemon in sync
after an Fn press. See [`keyboard-backlight-fix`](../keyboard-backlight-fix/)
for the full analysis.

A visible consequence: `systemd-backlight@leds:asus::kbd_backlight` saves `0`
at every shutdown and restores a dark keyboard at every boot. The service is
ordered `After=` it so the curve gets the last word.

**The sensor.** `iio:device1` (`name` = `als`), read through
`in_illuminance_raw` with the driver's `in_illuminance_scale` applied. Read
directly from sysfs rather than through iio-sensor-proxy's D-Bus API: the raw
attribute stays readable even while the proxy holds the IIO buffer claimed,
and it keeps the daemon free of any D-Bus dependency.

### Lock screens that blank the keyboard

A desktop that blanks the keyboard together with the display when a locked
screen goes dark, and restores it on wake, does so with `brightnessctl -s set
0` and `brightnessctl -r` (Omarchy does; the restore runs on every wake of
the unlock prompt). On this LED `-s` saves the dead read-back — always `0` —
so every restore turned the keyboard off behind the daemon's back, which
cannot see a write it did not make. Three things cover it: the daemon watches
the internal panel's DPMS node (`/sys/class/drm/card*-eDP-*/dpms`), stays
hands-off while the panel is off and re-applies the curve the moment it is
on; it re-writes its level every `reassert` seconds so any invisible write is
undone; and `sync_saved` keeps brightnessctl's per-session save file
(`$XDG_RUNTIME_DIR/brightnessctl/leds/<led>`) at the chosen level, so the
restores restore the right thing. The unit hides `/home` and `/root` with
`TemporaryFileSystem=` rather than `ProtectHome=`, because every mode of the
latter also covers `/run/user`, and runs with `ProtectSystem=full` and
`CAP_DAC_READ_SEARCH` so it can reach that file.

## Install

```sh
./patch.sh install keyboard-backlight-auto
```

Verify:

```sh
./patch.sh status keyboard-backlight-auto
sudo kbd-backlight-auto --status
```

Watch it decide in real time without letting it touch the backlight:

```sh
sudo kbd-backlight-auto --probe -v
```

```
17.3 lux | bucket 3 (12-32 lux, 70%) | would set level 2/3
20.4 lux | bucket 3 (12-32 lux, 70%) | level 2/3 (unchanged)
```

## Configuration

Everything is optional; `/etc/kbd-backlight-auto.conf` ships fully commented
out, and the built-in defaults are the values documented above. Restart with
`sudo systemctl restart kbd-backlight-auto` after editing.

| Key | Default | Purpose |
|---|---|---|
| `enabled` | `yes` | `no` makes the service exit immediately, leaving the backlight to the Fn keys |
| `led` | `/sys/class/leds/asus::kbd_backlight` | LED to drive |
| `interval` | `1.0` | Seconds between sensor samples |
| `bandwidth_hz` | `0.1` | Low-pass filter bandwidth; smaller is smoother, larger reacts faster |
| `calibration` | `1.0` | Multiplier on the lux reading before the curve is consulted |
| `curve` | Microsoft's | `<minlux>:<maxlux>:<percent>` triples |
| `override_lut` | Microsoft's | `<minlux>:<maxlux>:<lower>:<upper>` 4-tuples |
| `lid_off` | `yes` | Force the backlight off while the lid is shut |
| `reassert` | `5` | Re-write the chosen level this often (seconds) even when unchanged, so a write by something else is undone; `0` disables |
| `sync_saved` | `yes` | Keep brightnessctl's per-session saved level for this LED equal to the chosen level, so a desktop's `brightnessctl -r` restores the right value |

Invalid values are rejected per Microsoft's own validation rules — a curve with
gaps, no entries, or any bucket where `minlux ≥ maxlux` falls back to the
default and logs why.

### Calibration

The curve's thresholds are **absolute lux values**, so a mis-scaled sensor puts
the keyboard in the wrong bucket. The driver's `in_illuminance_scale` is
trusted by default (`calibration = 1.0`), which measured correctly on the
reference machine: about 18 lux in a curtained room with a single lamp, which
is where it should sit.

If the keyboard stays lit in a room that is obviously bright, the sensor reads
low — raise `calibration`. If it switches off far too early, lower it. Compare
`sudo kbd-backlight-auto --status` against a reference meter (any phone light
meter app is close enough for this) rather than guessing.

## Uninstall

```sh
./patch.sh uninstall keyboard-backlight-auto
```

Stops and disables the service and removes the daemon and unit.
`/etc/kbd-backlight-auto.conf` is left in place in case you edited it. The
backlight keeps whatever level it had; set it with the Fn keys.

## Sources

- [Keyboard Backlight Implementation Guide — Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/keyboard-backlight-implementation-guide)
  — the ALR curve, the manual-override lookup table, and the validation rules.
- [`gsd-power-manager.c` — GNOME](https://github.com/GNOME/gnome-settings-daemon/blob/master/plugins/power/gsd-power-manager.c)
  — `GSD_AMBIENT_BANDWIDTH_HZ`, `GSD_AMBIENT_TIME_CONSTANT`, and the smoothing
  in `iio_proxy_changed()`.
- [Computer light adjustment — US 7,839,379 (Apple)](https://patents.google.com/patent/US7839379B1/en)
  — the alternative monotonic model, for contrast.
