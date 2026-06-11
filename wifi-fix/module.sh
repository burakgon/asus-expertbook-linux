# wifi-fix module manifest. Sourced by ../patch.sh.
#
# ASUS ExpertBook Ultra (B9406CAA) ships an Intel Wi-Fi 7 BE211 (PCI
# 8086:e440 / subsystem 8086:0114) on Panther Lake CNVi, driven by the
# new iwlmld op_mode. On Linux 6.18 / 7.0 / 7.1-rc the Wi-Fi 7 / EHT
# (802.11be) path on this card is broken: EHT RX collapses to MCS0/NSS1
# and MLO sessions tear down, so the "Wi-Fi 7" link is in practice slower
# and flakier than plain Wi-Fi 6. Not fixed upstream as of 7.1-rc7.
#
# CORE FIX — disable EHT, fall back to Wi-Fi 6 (HE):
#
#   * iwlwifi disable_11be=Y.
#     Turns off 802.11be entirely. The card renegotiates as 802.11ax
#     (Wi-Fi 6 / HE), which is rock-solid at full speed (~2.1 Gbit/s at
#     160 MHz, verified). This is the same workaround Omarchy ships as
#     /etc/modprobe.d/iwlwifi-disable-eht.conf. Remove once Intel fixes
#     the iwlwifi EHT path upstream.
#
# SECONDARY TUNABLES — stabilize the Wi-Fi 6 fallback further:
# These don't keep Wi-Fi 7 alive; they just trim the remaining HE-mode
# instability (occasional missed-beacon / Microcode-SW-error events) and
# don't hurt. Each is independent and additive:
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
#   - Wi-Fi band / channel width below EHT — 6 GHz and 160 MHz HE stay
#     available; only the broken 802.11be/320 MHz EHT layer is dropped.
#   - Bluetooth coexistence — bt_coex_active stays at default Y so BT
#     audio / HID / file transfer all keep working.

MODULE_NAME="wifi-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) Intel BE211: disable broken EHT, stabilize Wi-Fi 6 fallback"
MODULE_VERSION="2.0.0"

MODULE_FILES=(
  "iwlwifi-disable-eht.conf:/etc/modprobe.d/iwlwifi-disable-eht.conf"
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

  echo "Reboot (or reload iwlwifi) to apply disable_11be=Y and"
  echo "iwlmld.power_scheme. ASPM and TSO/GSO have been applied to the"
  echo "running session already; the EHT-disable needs the driver reloaded."
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
  echo "Reboot to re-enable EHT (disable_11be) and revert"
  echo "iwlmld.power_scheme to the kernel default."
}

module_status_extra() {
  local cur="" iface link_summary aspm_policy off_state="?" eht=""

  # Core fix: is 802.11be (EHT) disabled? This is the indicator that the
  # actual BE211 bug is worked around. Y = EHT off -> stable Wi-Fi 6 fallback.
  if [[ -r /sys/module/iwlwifi/parameters/disable_11be ]]; then
    eht="$(cat /sys/module/iwlwifi/parameters/disable_11be 2>/dev/null || true)"
    case "$eht" in
      Y|y|1) printf '  EHT:      %sdisable_11be=Y (802.11be off — stable Wi-Fi 6/HE fallback)%s\n' "$c_ok" "$c_off" ;;
      N|n|0) printf '  EHT:      %sdisable_11be=N (802.11be ON — BE211 EHT is broken, expect MCS0/MLO teardown)%s\n' "$c_warn" "$c_off" ;;
      *)     printf '  EHT:      disable_11be=%s\n' "$eht" ;;
    esac
  else
    printf '  EHT:      %siwlwifi not loaded (cannot read disable_11be)%s\n' "$c_dim" "$c_off"
  fi

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
