# display-fix module manifest.
#
# ASUS ExpertBook Ultra (B9406CAA) Panther Lake iGPU + xe driver hangs the
# eDP-1 display engine when the panel uses Panel Replay Selective Update.
# Symptoms in dmesg:
#   xe 0000:00:02.0: [drm] *ERROR* Timed out waiting PSR idle state
#   xe 0000:00:02.0: [drm] *ERROR* [CRTC:151:pipe A] DSB 0 timed out waiting for idle
#   kwin_wayland: Pageflip timed out! This is a bug in the xe kernel driver
# and the internal panel goes black until reboot.
#
# Fix: disable PSR / Panel Replay on xe via kernel cmdline. modprobe.d
# alone is NOT enough on this distro — xe loads from initramfs before
# /etc/modprobe.d is honoured, so the params have to land on the kernel
# cmdline. We manage that by appending a marked block to
# /etc/default/limine (the source-of-truth that limine-entry-tool reads)
# and regenerating /boot/limine.conf.
#
# We still drop the modprobe.d file as belt-and-suspenders for any future
# scenario where xe is rmmod'd and re-loaded post-boot.

MODULE_NAME="display-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) xe driver Panel Replay PSR lockup workaround"
MODULE_VERSION="1.1.1"

MODULE_FILES=(
  "xe-disable-psr.conf:/etc/modprobe.d/xe-disable-psr.conf"
)

readonly _DF_LIMINE_CONF="/etc/default/limine"
readonly _DF_BEGIN="# >>> asus-expertbook-linux display-fix >>>"
readonly _DF_END="# <<< asus-expertbook-linux display-fix <<<"
readonly _DF_CMDLINE='KERNEL_CMDLINE[default]+=" xe.enable_psr=0 xe.enable_psr2_sel_fetch=0 xe.enable_panel_replay=0"'

_df_block_present() {
  [[ -f "$_DF_LIMINE_CONF" ]] && grep -qF "$_DF_BEGIN" "$_DF_LIMINE_CONF"
}

_df_append_block() {
  if [[ ! -f "$_DF_LIMINE_CONF" ]]; then
    echo "  warn: $_DF_LIMINE_CONF missing — skipping cmdline injection"
    return 0
  fi
  if _df_block_present; then
    echo "  cmdline marker already present in $_DF_LIMINE_CONF"
    return 0
  fi
  {
    printf '\n%s\n' "$_DF_BEGIN"
    printf '%s\n'   "$_DF_CMDLINE"
    printf '%s\n'   "$_DF_END"
  } >> "$_DF_LIMINE_CONF"
  echo "  appended cmdline marker to $_DF_LIMINE_CONF"
}

_df_remove_block() {
  if [[ ! -f "$_DF_LIMINE_CONF" ]] || ! _df_block_present; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v b="$_DF_BEGIN" -v e="$_DF_END" '
    BEGIN { skip=0; pending_blank="" }
    {
      if ($0 == b) { skip=1; next }
      if ($0 == e) { skip=0; next }
      if (skip) next
      if ($0 == "") { pending_blank = pending_blank ORS; next }
      else { printf "%s", pending_blank; pending_blank = ""; print }
    }
    END { printf "%s", pending_blank }
  ' "$_DF_LIMINE_CONF" > "$tmp"
  install -m 0644 "$tmp" "$_DF_LIMINE_CONF"
  rm -f "$tmp"
  echo "  removed cmdline marker from $_DF_LIMINE_CONF"
}

_df_regen_limine() {
  # limine-update is the right command on CachyOS / limine-mkinitcpio-hook;
  # it sources /etc/default/limine and rewrites /boot/limine.conf.
  # (limine-entry-tool only does single add/remove ops.)
  if command -v limine-update >/dev/null 2>&1; then
    echo "  regenerating /boot/limine.conf via limine-update"
    if ! limine-update >/dev/null 2>&1; then
      echo "  warn: limine-update exited non-zero — running mkinitcpio -P as fallback"
      mkinitcpio -P >/dev/null 2>&1 || true
    fi
  elif command -v mkinitcpio >/dev/null 2>&1; then
    echo "  limine-update not found — running mkinitcpio -P (triggers limine hook)"
    mkinitcpio -P >/dev/null 2>&1 || true
  else
    echo "  warn: neither limine-update nor mkinitcpio found — /boot/limine.conf NOT regenerated"
  fi
}

module_post_install() {
  _df_append_block
  _df_regen_limine
  echo
  echo "Reboot to apply: xe will load with PSR disabled on every kernel entry."
}

module_post_uninstall() {
  _df_remove_block
  _df_regen_limine
  echo
  echo "Reboot to revert: PSR will be re-enabled and the lockup may recur."
}

module_status_extra() {
  if grep -q 'xe\.enable_psr=0' /proc/cmdline 2>/dev/null; then
    printf '  cmdline: %sxe.enable_psr=0 active in current boot%s\n' "$c_ok" "$c_off"
  else
    if _df_block_present 2>/dev/null; then
      printf '  cmdline: %smarker present in %s — reboot to apply%s\n' "$c_warn" "$_DF_LIMINE_CONF" "$c_off"
    else
      printf '  cmdline: %sxe.enable_psr not on kernel cmdline%s\n' "$c_warn" "$c_off"
    fi
  fi

  if [[ -r /sys/kernel/debug/dri/0/i915_edp_psr_status ]]; then
    local mode
    mode="$(awk -F': ' '/^PSR mode:/ {print $2; exit}' /sys/kernel/debug/dri/0/i915_edp_psr_status 2>/dev/null)"
    if [[ -n "$mode" ]]; then
      case "$mode" in
        disabled*) printf '  panel:   %sPSR mode: %s%s\n' "$c_ok" "$mode" "$c_off" ;;
        *)         printf '  panel:   %sPSR mode: %s%s\n' "$c_warn" "$mode" "$c_off" ;;
      esac
    fi
  fi
}
