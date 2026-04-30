# wifi-fix module manifest. Sourced by ../patch.sh.
#
# ASUS ExpertBook Ultra (B9406CAA) ships an Intel Wi-Fi 7 BE211 (PCI
# 8086:e440 / subsystem 8086:0114) on Panther Lake CNVi, driven by the
# new iwlmld op_mode. Out of the box on Linux 6.18+ / 7.x the link is
# unstable on Wi-Fi 7 / 6 GHz / 320 MHz: kernel logs spam
# "missed beacons exceeds threshold, but receiving data" and throughput
# drops dramatically.
#
# This module bundles three independent fixes, each addressing one root
# cause documented for Wi-Fi 7 BE2xx Intel cards on Linux. They are
# additive — each one helps a different failure mode:
#
#   1) iwlmld power_scheme=1 (no driver-side power saving).
#      Default is 2 (balanced) which dips into short power-saves under
#      marginal SNR and trips the missed-beacon recovery path.
#
#   2) PCIe ASPM policy = performance (no L0s / L1 / L1.x).
#      The CNVi WiFi sits behind PCIe and the L1.2 wake latency is
#      enough to push some 802.11 timeouts past their threshold. Per-
#      device knobs in /sys/bus/pci/devices/.../link/ don't exist for
#      integrated endpoints, so we set the global ASPM policy. Side-
#      effect: ~1-3 W more idle power draw.
#
#   3) Disable TSO/GSO/GRO on iwlwifi interfaces.
#      The TX-segmentation offload path in iwlwifi has long-standing bugs
#      that, under heavy traffic, cause "Microcode SW error" + 10 second
#      freezes. Pushing segmentation onto the CPU is cheap on modern
#      Core Ultra silicon and avoids the freeze.
#
# This module *does not* touch:
#   - Wi-Fi band / channel width / protocol — Wi-Fi 7 stays Wi-Fi 7.
#   - Bluetooth coexistence — bt_coex_active stays at default Y so BT
#     audio / HID / file transfer all keep working.

MODULE_NAME="wifi-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) Intel Wi-Fi 7 BE211 stability fixes"
MODULE_VERSION="1.1.0"

MODULE_FILES=(
  "iwlmld-active.conf:/etc/modprobe.d/iwlmld-active.conf"
  "pcie-aspm-performance.conf:/etc/tmpfiles.d/pcie-aspm-performance.conf"
  "90-iwlwifi-no-offload:/etc/NetworkManager/dispatcher.d/90-iwlwifi-no-offload"
)

module_post_install() {
  # Make the dispatcher executable (install -m 0644 doesn't preserve +x).
  chmod 0755 /etc/NetworkManager/dispatcher.d/90-iwlwifi-no-offload \
    2>/dev/null || true

  # Apply the ASPM policy now (tmpfiles also does this on next boot).
  if [[ -w /sys/module/pcie_aspm/parameters/policy ]]; then
    echo performance > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
  fi

  # Apply the offload disable on every iwlwifi interface that's already up,
  # so the user sees the effect before rebooting.
  if command -v ethtool >/dev/null 2>&1; then
    for ifc in /sys/class/net/*; do
      [[ -L "$ifc/device/driver" ]] || continue
      drv=$(readlink "$ifc/device/driver" 2>/dev/null)
      [[ "$drv" == */iwlwifi ]] || continue
      ethtool -K "$(basename "$ifc")" tso off gso off gro off >/dev/null 2>&1 || true
    done
  fi

  echo "Reboot to fully apply iwlmld.power_scheme. ASPM and TSO/GSO have"
  echo "been applied to the running session already."
}

module_post_uninstall() {
  # Restore default ASPM policy in current session.
  if [[ -w /sys/module/pcie_aspm/parameters/policy ]]; then
    echo default > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
  fi
  # Re-enable offloads on iwlwifi interfaces.
  if command -v ethtool >/dev/null 2>&1; then
    for ifc in /sys/class/net/*; do
      [[ -L "$ifc/device/driver" ]] || continue
      drv=$(readlink "$ifc/device/driver" 2>/dev/null)
      [[ "$drv" == */iwlwifi ]] || continue
      ethtool -K "$(basename "$ifc")" tso on gso on gro on >/dev/null 2>&1 || true
    done
  fi
  echo "Reboot to revert iwlmld.power_scheme to the kernel default."
}

module_status_extra() {
  local cur="" iface link_summary aspm_policy off_state="?"

  if [[ -r /sys/module/iwlmld/parameters/power_scheme ]]; then
    cur="$(cat /sys/module/iwlmld/parameters/power_scheme 2>/dev/null || true)"
    case "$cur" in
      1) printf '  iwlmld:   %spower_scheme=1 (active — no power save)%s\n' "$c_ok" "$c_off" ;;
      2) printf '  iwlmld:   %spower_scheme=2 (balanced, kernel default)%s\n' "$c_warn" "$c_off" ;;
      3) printf '  iwlmld:   %spower_scheme=3 (low-power)%s\n' "$c_warn" "$c_off" ;;
      *) printf '  iwlmld:   power_scheme=%s\n' "$cur" ;;
    esac
  else
    printf '  iwlmld:   %sdriver not loaded%s\n' "$c_dim" "$c_off"
  fi

  if [[ -r /sys/module/pcie_aspm/parameters/policy ]]; then
    aspm_policy="$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true)"
    if [[ $aspm_policy == *"[performance]"* ]]; then
      printf '  ASPM:     %sperformance (no L0s/L1/L1.x — best for WiFi)%s\n' "$c_ok" "$c_off"
    elif [[ $aspm_policy == *"[default]"* ]]; then
      printf '  ASPM:     %sdefault (BIOS-configured, may dip into L1.x)%s\n' "$c_warn" "$c_off"
    else
      printf '  ASPM:     %s\n' "$aspm_policy"
    fi
  fi

  if command -v ethtool >/dev/null 2>&1 && command -v iw >/dev/null 2>&1; then
    iface="$(iw dev 2>/dev/null | awk '/Interface/ {print $2; exit}')"
    if [[ -n $iface ]]; then
      link_summary="$(iw dev "$iface" link 2>/dev/null \
        | awk '/freq:/ {f=$2} /signal:/ {s=$2} /SSID:/ {ssid=$2} END { if (ssid) printf "SSID=%s freq=%sMHz signal=%sdBm", ssid, f, s }')"
      [[ -n $link_summary ]] && printf '  link:     %s\n' "$link_summary"

      local tso gso gro
      tso=$(ethtool -k "$iface" 2>/dev/null | awk -F': ' '/^tcp-segmentation-offload:/ {print $2}')
      gso=$(ethtool -k "$iface" 2>/dev/null | awk -F': ' '/^generic-segmentation-offload:/ {print $2}')
      gro=$(ethtool -k "$iface" 2>/dev/null | awk -F': ' '/^generic-receive-offload:/ {print $2}')
      if [[ $tso == off* && $gso == off* && $gro == off* ]]; then
        printf '  offload:  %stso/gso/gro all off (workaround active on %s)%s\n' \
          "$c_ok" "$iface" "$c_off"
      else
        printf '  offload:  %stso=%s gso=%s gro=%s (dispatcher will fire on next link-up)%s\n' \
          "$c_warn" "$tso" "$gso" "$gro" "$c_off"
      fi
    fi
  fi
}
