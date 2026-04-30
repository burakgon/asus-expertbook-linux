# display-fix module manifest.
#
# ASUS ExpertBook Ultra (B9406CAA) Panther Lake iGPU + xe driver lockup.
# The internal panel supports Panel Replay Selective Update; the xe driver
# hangs trying to wake it, leaving the display black with KWin spamming
# pageflip timeouts. Permanently disabling PSR avoids the trigger.

MODULE_NAME="display-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) xe driver Panel Replay PSR lockup workaround"
MODULE_VERSION="1.0.0"

MODULE_FILES=(
  "xe-disable-psr.conf:/etc/modprobe.d/xe-disable-psr.conf"
)

module_post_install() {
  echo "Reboot to apply: xe will load with PSR disabled."
}

module_post_uninstall() {
  echo "Reboot to revert: PSR re-enabled (you may hit the lockup again)."
}

module_status_extra() {
  if [[ -r /sys/module/xe/parameters/enable_psr ]]; then
    local v
    v="$(cat /sys/module/xe/parameters/enable_psr 2>/dev/null || true)"
    case "$v" in
      0)  printf '  xe.enable_psr: %s0 (disabled — workaround active)%s\n' "$c_ok" "$c_off" ;;
      -1) printf '  xe.enable_psr: %s-1 (per-chip default; reboot to apply file)%s\n' "$c_warn" "$c_off" ;;
      *)  printf '  xe.enable_psr: %s\n' "$v" ;;
    esac
  fi
}
