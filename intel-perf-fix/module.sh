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
#   intel-lpmd (extra/      Intel Low Power Mode Daemon. When the system is
#   cachyos repo)           idle, parks all workload on a single LP-E core and
#                           lets the P-cores deep-sleep — biggest single
#                           idle-power win on PTL hardware. Stock config is
#                           Mode 0 (Cgroup v2 cpuset): it confines tasks to the
#                           LP-E cluster rather than offlining the P-cores.
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
MODULE_VERSION="1.1.0"

MODULE_FILES=()

module_post_install() {
  echo "  installing thermald (extra repo)"
  pacman -S --needed --noconfirm thermald 2>&1 | tail -3 || true

  echo "  enabling thermald.service"
  systemctl enable --now thermald.service 2>&1 | tail -1 || true

  echo
  echo "  installing intel-lpmd (extra/cachyos repo)"
  pacman -S --needed --noconfirm intel-lpmd 2>&1 | tail -3 || true

  echo "  enabling intel_lpmd.service"
  systemctl enable --now intel_lpmd.service 2>&1 | tail -1 || true
}

module_post_uninstall() {
  echo "  disabling thermald.service"
  systemctl disable --now thermald.service 2>/dev/null || true

  if systemctl list-unit-files intel_lpmd.service >/dev/null 2>&1; then
    systemctl disable --now intel_lpmd.service 2>/dev/null && echo "  disabled intel_lpmd.service"
  fi

  echo
  echo "  Packages left installed (so revert is reversible without re-fetching)."
  echo "  Remove fully with:"
  echo "    sudo pacman -Rns thermald"
  echo "    sudo pacman -Rns intel-lpmd"
}

module_status_extra() {
  local s
  for svc in thermald.service intel_lpmd.service; do
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
