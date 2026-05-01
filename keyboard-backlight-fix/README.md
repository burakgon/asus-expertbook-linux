# keyboard-backlight-fix

Make the keyboard-backlight slider in KDE Plasma actually reach the
embedded controller on the ASUS ExpertBook Ultra B9406CAA (BIOS
`B9406CAA.304`).

## The bug

The ASUS BIOS ships a broken `SLKB` ACPI method that handles keyboard
backlight write requests. Disassembled from the live DSDT:

```c
Method (SLKB, 1, NotSerialized) {
    If    ((Arg0 >= 0x0100) && (Arg0 <= 0x0106)) { Local0 = (Arg0 - 0x0100) }
    ElseIf((Arg0 >= 0x80)   && (Arg0 <= 0x83))   { Local0 = (Arg0 - 0x80) * 0x21 ... }
    ElseIf((Arg0 >= Zero)   && (Arg0 <= 0x03))   { Local0 = Zero }   // ← BUG
    STBC (Zero, Local0)
    Return (One)
}
```

The mainline `asus-wmi` Linux driver writes the standard kernel range
`0..3` to set keyboard brightness. That hits the third branch which
**unconditionally clamps `Local0` to zero**. The EC dutifully applies
"brightness = 0", and the keyboard backlight stays off forever no
matter what KDE / `brightnessctl` / direct `/sys/class/leds/` writes
do.

The OEM-tested `0x100..0x103` range works correctly — `Local0` ends up
as `0..3` as intended. The intermediate `0x80..0x83` range works too
(scaled by `0x21`).

## The fix

Userspace daemon **`asusd`** (shipped in `asusctl`) translates standard
kernel-level brightness writes into the OEM range before invoking ACPI,
side-stepping the buggy branch. Once `asusd` is running, KDE
PowerDevil's keyboard-brightness control reaches the EC correctly.

Three pieces have to be in place after a reboot for this to keep
working:

| File | Path | Why |
|---|---|---|
| `xyz.ljones.Asusd.service` | `/usr/share/dbus-1/system-services/` | `asusd.service` is `Type=dbus`, but ASUS doesn't ship the matching D-Bus activation entry. Without this file `asusd` never auto-starts even though the systemd unit is correct. We supply it so KDE / UPower's first request triggers `asusd`. |
| `acpi_call.conf` | `/etc/modules-load.d/` | Auto-load `acpi_call` at boot. Not strictly required for the running `asusd` path, but makes any follow-up debugging or fall-back tooling that pokes EC ACPI methods directly via `/proc/acpi/call` available without manual `modprobe`. |
| `/etc/asusd/` directory | (created in post_install) | `asusd` refuses to start without it; the `asusctl` package leaves it absent, so we `mkdir`. |

Plus two packages (installed by the post-install hook):

| Package | Source | Purpose |
|---|---|---|
| `asusctl` | `extra` repo | Provides `asusd`, the daemon that does the brightness-range translation. |
| `acpi_call-dkms` | AUR | Optional but useful: kernel module exposing `/proc/acpi/call` for direct ACPI invocations during debugging. |

## Install

```sh
./patch.sh install keyboard-backlight-fix
```

KDE keyboard-brightness slider should respond immediately. Verify:

```sh
./patch.sh status keyboard-backlight-fix
```

You should see:

```
  /etc/asusd dir:        present
  asusctl pkg:           6.3.7-1
  acpi_call-dkms pkg:    1.2.2-345.1
  acpi_call kmod:        loaded
  asusd:                 active (bus-activated by KDE/upower)
  UPower KbdBacklight:   max=3 (KDE talks here)
```

## Uninstall

```sh
./patch.sh uninstall keyboard-backlight-fix
```

Removes the activation file and the modules-load drop-in, stops `asusd`,
leaves `asusctl` and `acpi_call-dkms` installed for reversibility.
Remove packages fully with:

```sh
sudo pacman -Rns asusctl
paru -Rns acpi_call-dkms
```

## Note on the AUR step

`acpi_call-dkms` is only in the AUR. `paru` / `yay` need an interactive
`sudo` prompt during `makepkg → install`, which the patcher's scripted
post-install can't supply. Run it once manually after the rest:

```sh
paru -S acpi_call-dkms
```

The status command picks it up automatically once installed.

## Why not patch the BIOS / fix the ACPI table?

Replacing the broken `SLKB` method requires either a custom SSDT shipped
to override the firmware (possible via initramfs `acpi_override` but
fragile across kernel + BIOS upgrades) or a BIOS update from ASUS. Both
are heavier than running `asusd`, which already handles the translation
correctly and is shipped in distro repos for unrelated reasons.

If a future ASUS BIOS revision fixes the `SLKB` branch, this entire
module becomes redundant — uninstall.
