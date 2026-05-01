# intel-perf-fix module manifest.
#
# Brings the same Intel Panther Lake / Lunar Lake userspace power & thermal
# tuning that Omarchy 3.5/3.6 enables out of the box, on KDE Plasma + Arch.
# Specifically:
#
#   thermald (extra repo)   Intel thermal management daemon. P/E core throttle
#                           awareness, much better than the kernel's coarse
#                           default on Panther Lake's hybrid topology.
#
#   intel-lpmd (AUR)        Intel Low Power Mode Daemon. When the system is
#                           idle, parks all workload on a single LP-E core and
#                           lets the P-cores deep-sleep — biggest single
#                           idle-power win on PTL hardware.
#
# We deliberately DO NOT touch:
#   - The Hyprland-only toggles (Omarchy is Hyprland-based; we run KDE Plasma
#     which already handles touchpad / window scaling / lid the way we want).
#   - Dell-DMI-gated kernel patches (we proved earlier that the upstream
#     intel_quirks.c PCI subsystem entries match Dell only — 0x1028:0x0db9 —
#     and never trigger on our ASUS B9406CAA at 0x1043:0x15e4).
#   - power-profiles-daemon (already installed; coexists fine with thermald).
#
# This module ships no payload files; everything happens in the install hook
# (package installs + systemd unit enables). Empty MODULE_FILES is intentional
# and supported by patch.sh (mod_files_state treats empty as "all").

MODULE_NAME="intel-perf-fix"
MODULE_DESC="Panther Lake thermal + power daemons (thermald, intel-lpmd) à la Omarchy"
MODULE_VERSION="1.0.0"

MODULE_FILES=()

# Locate an AUR helper. paru/yay refuse to run as root; we re-invoke them as
# $SUDO_USER below.
_perf_aur_helper() {
  local h
  for h in paru yay; do
    command -v "$h" >/dev/null 2>&1 && { printf '%s' "$h"; return 0; }
  done
  return 1
}

module_post_install() {
  echo "  installing thermald (extra repo)"
  pacman -S --needed --noconfirm thermald 2>&1 | tail -3 || true

  echo "  enabling thermald.service"
  systemctl enable --now thermald.service 2>&1 | tail -1 || true

  echo
  local helper
  if helper="$(_perf_aur_helper)" && [[ -n "${SUDO_USER:-}" ]]; then
    echo "  installing intel-lpmd from AUR via $helper (as $SUDO_USER)"
    sudo -u "$SUDO_USER" "$helper" -S --needed --noconfirm intel-lpmd 2>&1 | tail -5 || true

    if systemctl list-unit-files intel_lpmd.service >/dev/null 2>&1; then
      echo "  enabling intel_lpmd.service"
      systemctl enable --now intel_lpmd.service 2>&1 | tail -1 || true
    elif systemctl list-unit-files lpmd.service >/dev/null 2>&1; then
      echo "  enabling lpmd.service"
      systemctl enable --now lpmd.service 2>&1 | tail -1 || true
    else
      echo "  warn: intel-lpmd installed but no systemd unit file found"
    fi
  else
    echo "  skip AUR step: no helper found or SUDO_USER unset"
    echo "  to finish manually: paru -S intel-lpmd && sudo systemctl enable --now intel_lpmd"
  fi
}

module_post_uninstall() {
  echo "  disabling thermald.service"
  systemctl disable --now thermald.service 2>/dev/null || true

  for svc in intel_lpmd.service lpmd.service; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
      systemctl disable --now "$svc" 2>/dev/null && echo "  disabled $svc"
    fi
  done

  echo
  echo "  Packages left installed (so revert is reversible without re-fetching)."
  echo "  Remove fully with:"
  echo "    sudo pacman -Rns thermald"
  echo "    paru   -Rns intel-lpmd"
}

module_status_extra() {
  local s
  for svc in thermald.service intel_lpmd.service lpmd.service; do
    s="$(systemctl is-active "$svc" 2>/dev/null || true)"
    case "$s" in
      active)        printf '  %-22s %sactive%s\n' "$svc" "$c_ok" "$c_off" ;;
      inactive|failed) printf '  %-22s %s%s%s\n' "$svc" "$c_warn" "$s" "$c_off" ;;
      "") ;;  # service unit doesn't exist; silent
    esac
  done

  if pacman -Q thermald >/dev/null 2>&1; then
    printf '  thermald pkg:          %s%s%s\n' "$c_ok" "$(pacman -Q thermald | awk '{print $2}')" "$c_off"
  else
    printf '  thermald pkg:          %snot installed%s\n' "$c_warn" "$c_off"
  fi
  if pacman -Q intel-lpmd >/dev/null 2>&1; then
    printf '  intel-lpmd pkg:        %s%s%s\n' "$c_ok" "$(pacman -Q intel-lpmd | awk '{print $2}')" "$c_off"
  else
    printf '  intel-lpmd pkg:        %snot installed%s\n' "$c_warn" "$c_off"
  fi
}
