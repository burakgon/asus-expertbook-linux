# ASUS ExpertBook Ultra (B9406CAA) — fingerprint fix on Linux

The FocalTech FT9349 fingerprint sensor (USB `2808:a97a`) works out of the box
with stock libfprint, driver "Focaltech MOC Sensors" (`focaltech_moc`):
`fprintd-enroll` and `fprintd-verify` work after a fresh boot. **No driver
change is needed.** After a suspend or hibernate, though, fprintd cannot open
the sensor again, and every fingerprint prompt (sudo, the lock screen, KDE's
Users page) fails until fprintd is restarted.

Confirmed reproducible on:

- ASUS ExpertBook Ultra (B9406CAA, 2026, Panther Lake), BIOS `B9406CAA.312`
- Kernel: `linux-cachyos 7.3.0`, Limine
- fprintd 1.94.5, libfprint 1.94.100 (CachyOS)

## The symptom

After resume:

```
$ fprintd-verify
failed to claim device: GDBus.Error:net.reactivated.Fprint.Error.Internal: Open failed with error: The device has already been opened!
```

KDE System Settings logs the same error
(`error claiming: "Open failed with error: The device has already been opened!"`).
The kernel log is clean: `dmesg` shows no USB error, disconnect or
re-enumeration for `2808:a97a` across the suspend, so the sensor itself comes
back fine. The fprintd process that was running before the suspend is still
the one answering after it, and it still holds the device as opened.

```sh
sudo systemctl restart fprintd
```

recovers it until the next suspend.

## Files

| File | Install path | What it does |
|---|---|---|
| `fprintd-reset` | `/usr/lib/systemd/system-sleep/` (mode 755) | systemd-sleep hook: stops `fprintd.service` before suspend/hibernate (`pre`) and restarts it after resume (`post`). |

Install also adds the `fprintd` package (it pulls in `libfprint`), which
Arch and CachyOS do not install by default. The package is called `fprintd`
on Debian/Ubuntu too.

fprintd is D-Bus activated, so it would also start again on the first
fingerprint request; the `post` restart just has it ready. The restarted
fprintd may log `Failed to install a sleep delay inhibitor: ... OperationInProgress`
because it starts while the sleep operation is still finishing. That is
harmless here: the hook stops it before the next sleep anyway.

## Install

```sh
./patch.sh install fingerprint-fix
```

No reboot needed; it applies from the next suspend. Enroll a finger with
`fprintd-enroll` if you have not yet.

By hand:

```sh
sudo pacman -S --needed fprintd
sudo install -D -m 0755 fprintd-reset /usr/lib/systemd/system-sleep/fprintd-reset
```

## Verify

```sh
./patch.sh status fingerprint-fix
# expect: hook: executable, fprintd: <version>, sensor: Focaltech MOC Sensors

systemctl suspend
# wake the laptop, then:
fprintd-verify
# expect: "Verify started!", touch the sensor, "verify-match (done)"
```

`journalctl -b -u fprintd` shows fprintd stopping just before each sleep and
starting again after resume.

## Uninstall

```sh
./patch.sh uninstall fingerprint-fix
```

Uninstall removes the hook and leaves `fprintd` installed, so enrolled
fingerprints keep working; it prints the command to remove the package.

By hand: delete `/usr/lib/systemd/system-sleep/fprintd-reset`.

## Notes

- Userspace only: no driver, kernel or libfprint change.
- The module does not edit PAM. Using the finger for sudo or login needs
  `pam_fprintd.so` in the matching `/etc/pam.d/` file, as with any fprintd
  setup; some desktops ship that already.
- On a machine without a fingerprint reader the hook does nothing harmful,
  and `status` reports the module as not applicable.
- Tested only on the B9406CAA, but nothing in the hook is specific to this
  sensor; it should help any fprintd setup that shows the same error after
  resume.
