# keyboard-backlight-fix module manifest.  ── OPTIONAL module ──
#
# IMPORTANT: the keyboard backlight already WORKS out of the box. The Fn
# brightness hotkeys are handled by the EC/BIOS at the hardware level and
# light the keyboard fine with no driver, no daemon, nothing installed.
# This module does NOT fix a dead backlight — it restores *software /
# OS-initiated* control (the KDE PowerDevil slider, brightnessctl, direct
# /sys/class/leds writes), which is the only path the firmware bug breaks.
# If you only ever use the Fn keys, you don't need this module at all.
#
# The ASUS ExpertBook Ultra (B9406CAA, BIOS B9406CAA.304) has a firmware
# bug in the SLKB ACPI method: when called with the standard 0..3
# brightness range that the Linux asus-wmi driver uses, the method's
# ElseIf branch *unconditionally clamps Local0 to zero* before passing it
# to STBC, which writes EC command 0xBC. Result: every OS-initiated write
# to /sys/class/leds/asus::kbd_backlight/brightness is silently turned
# into "set brightness 0", so the KDE slider / brightnessctl / sysfs path
# can't change the backlight — even though the Fn hotkeys (which don't go
# through SLKB) keep working.
#
# Method (SLKB, 1, NotSerialized) {
#     If    ((Arg0 >= 0x0100) && (Arg0 <= 0x0106)) { Local0 = (Arg0 - 0x0100) }
#     ElseIf((Arg0 >= 0x80)   && (Arg0 <= 0x83))   { Local0 = (Arg0 - 0x80) * 0x21 ... }
#     ElseIf((Arg0 >= Zero)   && (Arg0 <= 0x03))   { Local0 = Zero }    ← BUG
#     STBC (Zero, Local0)
#     Return (One)
# }
#
# Software-control fix: asusd (the userspace ASUS daemon) translates the
# standard kernel-level brightness writes into the OEM-tested 0x100..0x103
# range before passing them to ACPI/EC, side-stepping the buggy branch.
# Once asusd is running, KDE PowerDevil's keyboard-brightness control
# reaches the EC correctly.
#
# Upstream tracking: asus-armoury (mainline 6.19+) is gaining keyboard
# firmware-attributes that would expose kbd backlight under
# /sys/class/firmware-attributes/asus-armoury/attributes/kbd_* (Denis
# Benato LKML series, 2025-12-25). When a shipping kernel exposes that
# knob, the OS can set brightness through the correct ACPI range natively
# and this asusd workaround becomes unnecessary — track it, like
# display-fix tracks its upstream. As of 7.0.11 it is NOT present:
# asus-armoury here exposes only charge_mode + pending_reboot, no kbd_*.
#
# Three pieces have to be in place for this to work after reboot:
#
#   /etc/asusd/                  asusd refuses to start without the dir;
#                                ships empty in pacman/asusctl. We mkdir.
#
#   xyz.ljones.Asusd dbus        the asusd.service unit is Type=dbus, but
#   activation file              the matching activation entry isn't
#                                shipped, so dbus never auto-spawns it.
#                                We provide the activation file so any
#                                client (KDE PowerDevil) triggers asusd
#                                lazily on first use.
#
#   acpi_call (kernel module)    not strictly required for the running
#                                asusd path, but we autoload it so any
#                                follow-up debugging or fall-back tooling
#                                that pokes EC ACPI methods directly
#                                (e.g. /proc/acpi/call) is available.
#
# Packages required (installed via post_install hook): asusctl (extra),
# acpi_call-dkms (AUR via paru/yay).

MODULE_NAME="keyboard-backlight-fix"
MODULE_DESC="Make KDE-controlled keyboard backlight reach the EC despite ASUS BIOS SLKB firmware bug"
MODULE_VERSION="1.1.0"

MODULE_FILES=(
  "xyz.ljones.Asusd.service:/usr/share/dbus-1/system-services/xyz.ljones.Asusd.service"
  "acpi_call.conf:/etc/modules-load.d/acpi_call.conf"
)

_kbf_aur_helper() {
  local h
  for h in paru yay; do
    command -v "$h" >/dev/null 2>&1 && { printf '%s' "$h"; return 0; }
  done
  return 1
}

module_post_install() {
  echo "  installing asusctl (extra repo)"
  pacman -S --needed --noconfirm asusctl 2>&1 | tail -3 || true

  echo "  ensuring /etc/asusd directory exists (asusd refuses to start without it)"
  install -d -m 0755 /etc/asusd

  echo "  reloading dbus daemon (pick up the new activation file)"
  systemctl reload dbus 2>/dev/null || systemctl reload dbus.socket 2>/dev/null || true

  echo
  echo "  acpi_call-dkms is in the AUR. paru/yay needs an interactive sudo"
  echo "  prompt during makepkg→install which scripted post_install can't"
  echo "  supply. Run separately if not already installed:"
  echo "      paru -S acpi_call-dkms"
  echo

  # Load acpi_call now if available.
  if ! lsmod | grep -q '^acpi_call'; then
    if modprobe acpi_call 2>/dev/null; then
      echo "  loaded acpi_call now"
    else
      echo "  acpi_call not yet installed — skip"
    fi
  fi

  # Trigger asusd via dbus so the user gets working backlight in *this*
  # session without having to log out + back in.
  if ! systemctl is-active --quiet asusd; then
    busctl --system call xyz.ljones.Asusd /xyz/ljones/Asusd \
      org.freedesktop.DBus.Peer Ping >/dev/null 2>&1 || \
      systemctl start asusd 2>/dev/null || true
  fi

  echo
  echo "Done. KDE keyboard-brightness slider should work immediately."
  echo "Verify with: ./patch.sh status keyboard-backlight-fix"
}

module_post_uninstall() {
  echo "  reloading dbus daemon (drop the activation file)"
  systemctl reload dbus 2>/dev/null || systemctl reload dbus.socket 2>/dev/null || true

  if systemctl is-active --quiet asusd; then
    echo "  stopping asusd (was bus-activated; will only auto-start again if reinstalled)"
    systemctl stop asusd 2>/dev/null || true
  fi

  echo
  echo "  Packages (asusctl, acpi_call-dkms) left installed for revert without"
  echo "  re-fetching. Remove fully with:"
  echo "    sudo pacman -Rns asusctl"
  echo "    paru -Rns acpi_call-dkms"
}

module_status_extra() {
  if [[ -d /etc/asusd ]]; then
    printf '  /etc/asusd dir:        %spresent%s\n' "$c_ok" "$c_off"
  else
    printf '  /etc/asusd dir:        %sMISSING — asusd will refuse to start%s\n' "$c_warn" "$c_off"
  fi

  if pacman -Q asusctl >/dev/null 2>&1; then
    printf '  asusctl pkg:           %s%s%s\n' "$c_ok" "$(pacman -Q asusctl | awk '{print $2}')" "$c_off"
  else
    printf '  asusctl pkg:           %snot installed%s\n' "$c_warn" "$c_off"
  fi
  if pacman -Q acpi_call-dkms >/dev/null 2>&1; then
    printf '  acpi_call-dkms pkg:    %s%s%s\n' "$c_ok" "$(pacman -Q acpi_call-dkms | awk '{print $2}')" "$c_off"
  else
    printf '  acpi_call-dkms pkg:    %snot installed (paru -S acpi_call-dkms)%s\n' "$c_warn" "$c_off"
  fi

  if [[ -d /sys/module/acpi_call ]]; then
    printf '  acpi_call kmod:        %sloaded%s\n' "$c_ok" "$c_off"
  else
    printf '  acpi_call kmod:        %snot loaded%s\n' "$c_dim" "$c_off"
  fi

  local asusd_state
  asusd_state="$(systemctl is-active asusd 2>/dev/null || true)"
  case "$asusd_state" in
    active)        printf '  asusd:                 %sactive (bus-activated by KDE/upower)%s\n' "$c_ok" "$c_off" ;;
    *)             printf '  asusd:                 %s%s — should auto-start when KDE polls UPower%s\n' "$c_dim" "$asusd_state" "$c_off" ;;
  esac

  # The only check that actually proves software control works: write a
  # value to the LED brightness node and read it back. With the SLKB bug
  # and asusd absent, the EC clamps to 0 so the read-back never matches.
  # (UPower advertising max=3 does NOT prove this — see below — so it is
  # informational only, not a pass/fail signal.)
  local led=/sys/class/leds/asus::kbd_backlight/brightness
  if [[ -w "$led" ]]; then
    local orig target readback
    orig="$(cat "$led" 2>/dev/null)"
    # Pick a non-zero target distinct from current so a stuck-at-0 (or
    # stuck-at-current) clamp is detectable.
    if [[ "$orig" == "1" ]]; then target=2; else target=1; fi
    if printf '%s' "$target" > "$led" 2>/dev/null; then
      readback="$(cat "$led" 2>/dev/null)"
      if [[ "$readback" == "$target" ]]; then
        printf '  sysfs write test:      %sOK — wrote %s, read back %s (software control works)%s\n' \
          "$c_ok" "$target" "$readback" "$c_off"
      else
        printf '  sysfs write test:      %sFAILED — wrote %s, read back %s (SLKB clamp; asusd not translating)%s\n' \
          "$c_err" "$target" "$readback" "$c_off"
      fi
      # Restore whatever was there before the probe.
      printf '%s' "$orig" > "$led" 2>/dev/null || true
    else
      printf '  sysfs write test:      %scould not write %s (permission?)%s\n' "$c_dim" "$led" "$c_off"
    fi
  else
    printf '  sysfs write test:      %sLED node not writable/present (%s)%s\n' "$c_dim" "$led" "$c_off"
  fi

  # Informational only: UPower exposes max=3 even when the fix is absent
  # and software control is broken, so this is NOT a "fixed" indicator.
  if command -v busctl >/dev/null 2>&1; then
    local maxb
    maxb="$(busctl --system call org.freedesktop.UPower /org/freedesktop/UPower/KbdBacklight \
            org.freedesktop.UPower.KbdBacklight GetMaxBrightness 2>/dev/null \
            | awk '{print $NF}')"
    if [[ -n "$maxb" ]]; then
      printf '  UPower KbdBacklight:   %smax=%s (info only — present even when control is broken)%s\n' "$c_dim" "$maxb" "$c_off"
    fi
  fi
}
