# B9406CAA desktop freeze

ASUS ExpertBook Ultra B9406CAA. Samsung eDP panel ATNA40LE01-0. Intel Arc
B390 (`8086:b080`). PixArt haptic touchpad `093A:4F05`, ACPI name
`ASCP1D80`, on `i2c_designware.0`.

Two different failures both end with a frozen desktop. Check which one you
have before changing boot parameters. A machine can have both. On stock
(non-CachyOS) 7.2.y kernels there is a third, trace-less one; see
[Stock 7.2 kernels](#stock-72-kernels).

The touchpad wedge below was logged on Omarchy 4.0.4 with stock
`linux 7.2.3-arch1-3`. The same touchpad bus and the same panel exist on
other distros. `linux-omarchy 7.2.5` was installed on the machine that
produced these logs and was not the kernel that froze.

Search terms: `timeout waiting for bus ready`, `controller timed out`,
`timeout in disabling adapter`, `ASCP1D80`, `i915_flip`, `ISHTP`,
`Timed out waiting PSR idle state`, `xe.enable_panel_replay=0`, `SU_STANDBY`.

## Which failure is it?

```sh
ps -eo etimes,stat,pid,wchan:24,cmd | awk 'NR==1 || $2 ~ /^D/'
journalctl -k -b --no-pager | grep -E 'controller timed out|timeout in disabling adapter|timeout waiting for bus ready|ISHTP device' | tail -n 20
journalctl -k -b --no-pager | grep -E 'PSR idle state|DSB|FIFO underrun|Pageflip' | tail -n 20
tr ' ' '\n' < /proc/cmdline | grep -E 'enable_psr|enable_panel_replay|enable_dpcd_backlight'
ls -l /etc/limine-entry-tool.d/ /etc/modprobe.d/xe-dpcd-backlight.conf
```

### 1. Touchpad I2C wedge

The kernel log grows in this order:

```
i2c_designware i2c_designware.0: controller timed out
i2c_designware i2c_designware.0: timeout in disabling adapter
i2c_designware i2c_designware.0: timeout waiting for bus ready
```

The last line repeats about twenty times a second until reboot. The
`ASCP1D80` threaded IRQ and `kworker/*+i915_flip` sit in `D` state, so the
picture stops updating, not only the cursor. `hid-sensor-hub ... timeout
waiting for response from ISHTP device` can show up a few minutes earlier.

Three boots on linux 7.2.3 ended this way, each time only at the end of a
long session:

| Session | Flood started | `timeout waiting for bus ready` lines |
|---|---|---|
| 19 Sep 18:48 → 20 Sep 15:59 | 20 Sep 15:56 | 3935 |
| 20 Sep 16:00 → 22 Sep 09:58 | 22 Sep 09:33, 41 seconds after resume | 13382 |
| 22 Sep 21:11 → 25 Sep 19:14 | 25 Sep 19:01 | 14186 |

The boot from 15 Sep 19:59 to 18 Sep 20:31, the one immediately after Omarchy
4.0.4, logged none of these lines. These journals did not contain
`Timed out waiting PSR idle state` or a DSB timeout, so the display
parameters below are not claimed as a cure for this wedge.

`i915_flip` in `D` by itself is not this bug. After the 25 Sep reboot, with
Panel Replay already disabled and with zero I2C timeouts, two `i915_flip`
workers still stayed in `D` for many minutes.

### 2. Display self-refresh

`/proc/cmdline` lacks the PSR1 pair, or the kernel log shows
`Timed out waiting PSR idle state`, DSB errors or FIFO underruns.
`display-fix` 1.4 puts `xe.enable_panel_replay=0 xe.enable_psr=1` on the
cmdline. The older `xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0`
pair reaches the same PSR1 mode, because Panther Lake has no PSR2 hardware
tracking to fall back on without selective fetch.

`display-fix` 1.3 left only `xe.enable_dpcd_backlight=2` on the cmdline and
archived Omarchy's own
`/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf`
(`fix-asus-ptl-b9406-display.sh`, [omarchy#5423](https://github.com/omacom/omarchy/issues/5423)),
which is how Omarchy keeps `xe.enable_panel_replay=0` on this laptop. Issue
[#7](https://github.com/burakgon/asus-expertbook-linux/issues/7) asked to try
dropping `xe.enable_psr=0` while keeping the other two switches. Version 1.3
dropped all three. On 7.2.0 that brought back PSR idle timeouts, DSB poll
errors, a FIFO underrun and on-screen corruption; on 7.2.2 and 7.2.4 it
showed as washed-out HDR, stale frames, flicker and VRR smearing.

`xe.enable_psr=0` does not disable Panel Replay. Turning Panel Replay off by
itself falls back to PSR2 selective update. On 25 Sep 2026, on an already
wedged boot, that fallback was seen parked in `SU_STANDBY` and the hitching
continued. That is why 1.4 turns off PSR2 as well, and leaves PSR1 running.

## Recover the touchpad

While the session still accepts a command, rebind the touchpad's I2C-HID
driver. On Omarchy:

```sh
omarchy restart trackpad
```

Anywhere else:

```sh
dev=i2c-ASCP1D80:00
echo "$dev" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
sleep 1
echo "$dev" | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
```

The touchscreen (`ILIT2901`) sits on `i2c_designware.1`, so it does not need
the rebind. Then:

```sh
journalctl -k -b --since "30 seconds ago" --no-pager | grep -c 'timeout waiting for bus ready'
```

Zero new lines and a cursor that moves means this incident is over.

If the touchpad rebind does not clear the flood, rebind the I2C controller
itself (it can hang the same way if the controller is fully stuck):

```sh
echo i2c_designware.0 | sudo tee /sys/bus/platform/drivers/i2c_designware/unbind
sleep 1
echo i2c_designware.0 | sudo tee /sys/bus/platform/drivers/i2c_designware/bind
```

Rebinding the controller recovered the same timeout loop on an AMD laptop with
a PixArt pad ([kernel bugzilla 221190](https://bugzilla.kernel.org/show_bug.cgi?id=221190)).

If the rebind hangs, or `irq/*-ASCP1D80` is already in `D`:

- Do not `rmmod` the touchpad, the GPU, or audio. The stuck thread does not
  release.
- Do not suspend. Resume is one of the observed starts of this wedge.
- Reboot. On Omarchy, with nothing stuck in `D`, run `omarchy system reboot`.
  With `i915_flip` or the touchpad IRQ stuck in `D`, a normal reboot can leave
  the last frame on screen until the machine actually powers off, so expect
  that, or use `systemctl reboot --force --no-wall`. If the session is already
  frozen solid, hold the power button.

The reporter isolated a recurring stall to a status-bar widget that polled
`acpitz` (`/sys/class/hwmon/hwmon*/temp1_input`) in a loop. Those reads run
ACPI methods on the embedded controller. Until this is understood, do not
poll `acpitz` or ASUS `hwmon` fan and temperature nodes from a status bar;
`coretemp` is the safer CPU temperature source. The libinput pressure quirk
(`touchpad-fix`) stops "Touch jump detected and discarded". It does not
prevent this wedge.

## Narrowing it down

No upstream fix exists yet. These comparisons would tell kernel developers
where to look:

- **Kernel A/B.** Linux 7.2 changed `i2c-designware` (`f5cfe0a71588`, "Handle
  active target cleanly"), and an Acer with an ELAN pad reports a similar
  7.1→7.2 regression that the LTS kernel does not show
  ([omarchy#11245](https://github.com/omacom/omarchy/issues/11245)). Run
  6.18 LTS or 7.3-rc for a few days and compare.
- **Runtime PM.** Both `0000:00:19.0` and `i2c_designware.0` runtime-suspend
  after 1 s idle (`power/control=auto`). Pinning them on is a cheap test:
  `echo on | sudo tee /sys/bus/pci/devices/0000:00:19.0/power/control /sys/bus/platform/devices/i2c_designware.0/power/control`
  (resets at reboot).
- **Sensor hub.** The ISHTP timeout that preceded one wedge appears when the
  Intel Sensor Hub is runtime-suspended; `ish-firmware` keeps it on. Report
  `cat /sys/bus/pci/devices/0000:00:12.0/power/control` with any new incident.

If it still reproduces on 7.3-rc, report it to linux-i2c and linux-input with
the journal. Do not unbind the audio driver as a recovery step either: an
unbind oops on this machine's CS35L56 matches an IRQ lifetime bug with a fix
still under review.

## Stock 7.2 kernels

Linux 7.2 carries only half of the fix for a trace-less hard freeze caused by
display page tables and framebuffers in stolen memory (drm/xe #7513). The
second half, `0687ec06f51b` ("drm/xe/display: Do not allocate into stolen for
new framebuffers"), is in 7.3 and not in 7.2.y stable. Two X7 358H machines
froze on stock 7.2 without it
([CachyOS#986](https://github.com/CachyOS/linux-cachyos/issues/986)); CachyOS
kernels carry it since 7.2.1. On Arch's or Omarchy's stock 7.2.y a freeze with
no I2C flood and no PSR/DSB line can be this one; 7.3 or the 6.18 LTS avoids it.

### Confirmed on B9406CAA (14 Oct 2026)

Omarchy 4.0.4, stock `linux 7.2.3-arch1-3`, display-fix 1.4 already on the
cmdline (`xe.enable_panel_replay=0 xe.enable_psr=1 xe.enable_dpcd_backlight=2`).
After ~14.5 h uptime the desktop entered a repeating hitch: audio replayed the
same buffer for ~5 s, the session advanced ~2 s, then hitch again, until a
power-key reboot hung on `session-1.scope` timeout and needed a hard reset.

Classify against the other two failures:

| Check | Result |
|---|---|
| `timeout waiting for bus ready` | 0 |
| `controller timed out` / ISHTP | 0 |
| `PSR idle` / DSB / Pageflip | 0 |
| `Allocated fbdev into stolen` | present at boot |
| `not enough stolen space for compressed buffer` | present |
| PipeWire near the end | `hw:sofsoundwire,0p: snd_pcm_avail after recover: Broken pipe` |
| Mute-LED sync | `omarchy-audio-output-sink` timed out after 3 s (twice) |

`linux-omarchy 7.2.5-3` was already installed. Its `xe.ko` no longer contains
the `Allocated fbdev into stolen` strings; stock `7.2.3-arch1-3` still does.
Limine was set to `default_entry: Omarchy/linux`, so every boot kept the
vulnerable kernel even though `BOOT_ORDER` listed `linux-omarchy` first.

Recovery on Omarchy:

```sh
# Prefer the kernel that already carries the stolen-FB backport
sudo sed -i 's|^default_entry: Omarchy/linux$|default_entry: Omarchy/linux-omarchy|' /boot/limine.conf
# Drop Limine's last-booted override if present
efivar=LimineLastBootedEntry-513ee0d0-6e43-cb05-b272-f146a2fcb88a
sudo chattr -i /sys/firmware/efi/efivars/$efivar 2>/dev/null
sudo rm -f /sys/firmware/efi/efivars/$efivar
```

After reboot, confirm:

```sh
uname -r    # expect 7.2.5-3-omarchy (or newer linux-omarchy)
journalctl -k -b --no-pager | grep -i stolen
# expect NO "Allocated fbdev into stolen"
```

Alternatives when `linux-omarchy` is unavailable: Linux 7.3+, CachyOS 7.2.1+
(carries `0687ec06f51b`), or the 6.18 LTS.

## Put the display parameters back

`xe` loads from the initramfs, so `modprobe.d` alone does nothing on the next
boot. The parameters have to be on the kernel command line.

```sh
./patch.sh install display-fix
sudo reboot
```

`display-fix` 1.4 writes
`/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf`:

```
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=2 xe.enable_panel_replay=0 xe.enable_psr=1"
```

and `/etc/modprobe.d/xe-dpcd-backlight.conf`, for a later reload of `xe` only:

```
options xe enable_dpcd_backlight=2 enable_panel_replay=0 enable_psr=1
```

It also moves Omarchy's drop-in back if 1.3 archived it. It keeps a copy
archived only when that copy sets `xe.enable_psr` or `xe.enable_panel_replay`
to another value, such as a hand-edited `xe.enable_psr=0`, because the file
sorts after `90-asus-expertbook-linux-display.conf` and would win on the
cmdline. To restore Omarchy's copy by hand:

```sh
archived=/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf.disabled-by-asus-expertbook-linux
live=/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf
sudo test -f "$archived" && sudo test ! -e "$live" && sudo mv "$archived" "$live"
sudo limine-update
```

Reboot with the rule in the previous section. Confirm after boot:

```sh
tr ' ' '\n' < /proc/cmdline | grep -E 'enable_panel_replay|enable_psr|enable_dpcd_backlight'
sudo ./patch.sh status display-fix    # expect "PSR mode: PSR1 enabled"
```

With VRR active the driver keeps PSR off, so the debugfs line reads
`disabled` there; that is expected.

## After an Omarchy update

Run the commands at the top before deciding the update was clean. Omarchy
4.0.4 itself was followed by a three-day boot with no I2C flood. The display
failure that came back was display-fix 1.3 deleting Omarchy's
`xe.enable_panel_replay=0` drop-in; 1.4 no longer does that. The touchpad
wedge has also returned on its own after a day or two, including immediately
after resume, with no package update in that minute.

## Reports

- Omarchy: [omacom/omarchy#13274](https://github.com/omacom/omarchy/issues/13274)
- Display-fix 1.3 retirement: [asus-expertbook-linux#7](https://github.com/burakgon/asus-expertbook-linux/issues/7)
- Stolen-memory freeze (stock 7.2): [CachyOS/linux-cachyos#986](https://github.com/CachyOS/linux-cachyos/issues/986), upstream [drm/xe#7513](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/7513)
- PSR1 pinning: [asus-expertbook-linux#8](https://github.com/burakgon/asus-expertbook-linux/pull/8)
- Omarchy drop-in restore and the first version of this document: [asus-expertbook-linux#22](https://github.com/burakgon/asus-expertbook-linux/pull/22)
- Original Panel Replay stall, different bug (first frame never updates, fixed by `xe.enable_panel_replay=0` alone on an older kernel): [omacom/omarchy#5423](https://github.com/omacom/omarchy/issues/5423)
