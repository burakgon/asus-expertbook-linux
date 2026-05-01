# display-hdr-fix module manifest.
#
# ASUS ExpertBook Ultra (B9406CAA) ships a Samsung Display ATNA40LE01-0
# 14" 2880x1800 OLED panel that's HDR-capable: DCI-P3 + BT.2020/SMPTE
# ST 2084 (HDR PQ EOTF), 700 cd/m² full-coverage, 1600 cd/m² peak,
# 12 bpc native, 30-120 Hz VRR — DisplayHDR True Black 1000 class.
#
# But: the xe driver fails to read the panel EDID over the eDP DDC/AUX
# channel. /sys/class/drm/card0-eDP-1/edid returns 0 bytes. With no
# EDID, the kernel hands KDE/KWin no panel metadata, so kscreen-doctor
# reports:
#     HDR: incapable
#     Wide Color Gamut: incapable
# even though the compositor (KWin Wayland) has full HDR pipeline
# support (wp_color_manager_v1 with set_luminances + supported_tf for
# PQ ST2084). KDE refuses to enable HDR because, from its view, the
# display is SDR-only.
#
# Without HDR enabled, the entire pipeline downgrades:
#   - YouTube AV1-HDR videos play in SDR (Vivaldi/Chromium tone-maps
#     down because the surface is sRGB)
#   - 10-bit deep colour disabled (8-bit RGB only)
#   - DCI-P3 wide gamut unused (sRGB clipping)
#
# Workaround: ASUS thoughtfully stashes the panel's full EDID
# (including the DisplayID 2.0 extension block with HDR specs) in an
# EFI variable named `AsusEDID-607005d5-3f75-4b2e-98f0-85ba66797a3e`.
# We extracted that 256-byte EDID and ship it as a firmware override.
#
# Two pieces have to be in place after a reboot:
#
#   asus-b9406-edid.bin → /usr/lib/firmware/edid/
#       The EDID payload that DRM will load instead of trying (and
#       failing) to fetch over DDC.
#
#   drm.edid_firmware=eDP-1:edid/asus-b9406-edid.bin on kernel cmdline
#       Tells DRM "for connector eDP-1, use this file." Same approach
#       as display-fix's xe.enable_psr=0 — has to be on the cmdline
#       because xe loads from initramfs before /etc/modprobe.d.
#
# After the reboot, kscreen-doctor will report:
#     HDR: enabled-when-content-is-HDR (or capable)
#     Wide Color Gamut: capable
# and KDE Display Settings → Display → "Enable HDR" toggle becomes
# available. With HDR on, Vivaldi snapshot's HDR video pipeline
# activates (Wayland color management + 10-bit AV1 decode + PQ
# transfer function), and YouTube HDR videos play in true HDR.
#
# If a future xe driver revision (or a kernel patch) starts reading
# the panel EDID correctly over DDC, this module becomes redundant —
# uninstall it.

MODULE_NAME="display-hdr-fix"
MODULE_DESC="Inject ASUS-supplied panel EDID so xe driver exposes HDR / DCI-P3 to KDE"
MODULE_VERSION="1.0.2"

MODULE_FILES=(
  "asus-b9406-edid.bin:/usr/lib/firmware/edid/asus-b9406-edid.bin"
  "asus-b9406-edid.mkinitcpio.conf:/etc/mkinitcpio.conf.d/asus-b9406-edid.conf"
)

readonly _DH_LIMINE_CONF="/etc/default/limine"
readonly _DH_BEGIN="# >>> asus-expertbook-linux display-hdr-fix >>>"
readonly _DH_END="# <<< asus-expertbook-linux display-hdr-fix <<<"
readonly _DH_CMDLINE='KERNEL_CMDLINE[default]+=" drm.edid_firmware=eDP-1:edid/asus-b9406-edid.bin"'
readonly _DH_EFI_VAR="/sys/firmware/efi/efivars/AsusEDID-607005d5-3f75-4b2e-98f0-85ba66797a3e"
# EDID we ship is patched: ASUS's stored EDID claims 2 extension blocks
# but ships only 1 (256 byte file), which xe rejects as Invalid. We
# fix byte 126 = 0x01 and recompute base-block checksum (byte 127). The
# raw EFI variable bytes are different from this — that's fine.
readonly _DH_EDID_SHA="6609e337dfe7aec217b3fb2e444cd50fc62d9fac18611e30198a74c1544df1c2"
readonly _DH_EFI_RAW_SHA="841655f043ac8984f40c8393f6224aa75d34ae51c0c2c5d4faa9b6565685014f"

_dh_block_present() {
  [[ -f "$_DH_LIMINE_CONF" ]] && grep -qF "$_DH_BEGIN" "$_DH_LIMINE_CONF"
}

_dh_append_block() {
  if [[ ! -f "$_DH_LIMINE_CONF" ]]; then
    echo "  warn: $_DH_LIMINE_CONF missing — skipping cmdline injection"
    return 0
  fi
  if _dh_block_present; then
    echo "  cmdline marker already present in $_DH_LIMINE_CONF"
    return 0
  fi
  {
    printf '\n%s\n' "$_DH_BEGIN"
    printf '%s\n'   "$_DH_CMDLINE"
    printf '%s\n'   "$_DH_END"
  } >> "$_DH_LIMINE_CONF"
  echo "  appended cmdline marker to $_DH_LIMINE_CONF"
}

_dh_remove_block() {
  if [[ ! -f "$_DH_LIMINE_CONF" ]] || ! _dh_block_present; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  awk -v b="$_DH_BEGIN" -v e="$_DH_END" '
    BEGIN { skip=0; pending_blank="" }
    {
      if ($0 == b) { skip=1; next }
      if ($0 == e) { skip=0; next }
      if (skip) next
      if ($0 == "") { pending_blank = pending_blank ORS; next }
      else { printf "%s", pending_blank; pending_blank = ""; print }
    }
    END { printf "%s", pending_blank }
  ' "$_DH_LIMINE_CONF" > "$tmp"
  install -m 0644 "$tmp" "$_DH_LIMINE_CONF"
  rm -f "$tmp"
  echo "  removed cmdline marker from $_DH_LIMINE_CONF"
}

_dh_regen_limine() {
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

_dh_regen_initramfs() {
  # The EDID firmware has to be baked into initramfs because xe loads in
  # early KMS (before rootfs is mounted). The drop-in file at
  # /etc/mkinitcpio.conf.d/asus-b9406-edid.conf appends the EDID to FILES,
  # so a plain `mkinitcpio -P` is enough to embed it.
  if command -v mkinitcpio >/dev/null 2>&1; then
    echo "  regenerating initramfs via mkinitcpio -P (embeds EDID for early KMS)"
    if ! mkinitcpio -P >/dev/null 2>&1; then
      echo "  warn: mkinitcpio -P exited non-zero — early KMS may still miss the EDID"
    fi
  else
    echo "  warn: mkinitcpio not found — initramfs NOT regenerated"
  fi
}

_dh_verify_efi_match() {
  # Sanity check: confirm the raw ASUS-stored EDID on this system still
  # matches what we patched our shipped file from. If a BIOS update
  # changes the EDID payload, the patched file we ship is stale.
  if [[ -r "$_DH_EFI_VAR" ]]; then
    local efi_sha
    efi_sha="$(dd if="$_DH_EFI_VAR" bs=1 skip=4 status=none 2>/dev/null | sha256sum | awk '{print $1}')"
    if [[ "$efi_sha" != "$_DH_EFI_RAW_SHA" ]]; then
      echo "  warn: ASUS EFI EDID payload differs from the version we patched"
      echo "        shipped (raw source): $_DH_EFI_RAW_SHA"
      echo "        EFI on this system:   $efi_sha"
      echo "        BIOS may have been updated; please report at"
      echo "        https://github.com/burakgon/asus-expertbook-linux/issues"
    fi
  fi
}

module_post_install() {
  _dh_verify_efi_match
  _dh_append_block
  _dh_regen_initramfs
  _dh_regen_limine
  echo
  echo "Reboot to apply. After boot:"
  echo "   1. kscreen-doctor -o    # 'HDR: capable' should appear"
  echo "   2. System Settings → Display → toggle 'Enable HDR'"
  echo "   3. YouTube HDR video in Vivaldi will play in HDR"
}

module_post_uninstall() {
  _dh_remove_block
  _dh_regen_initramfs
  _dh_regen_limine
  echo
  echo "Reboot to revert. xe will retry DDC EDID readback on the next"
  echo "boot — if the kernel side is fixed by then, HDR will continue to"
  echo "work without this module."
}

module_status_extra() {
  if grep -q 'drm\.edid_firmware=eDP-1' /proc/cmdline 2>/dev/null; then
    printf '  cmdline:    %sdrm.edid_firmware active in current boot%s\n' "$c_ok" "$c_off"
  else
    if _dh_block_present 2>/dev/null; then
      printf '  cmdline:    %smarker in %s — reboot to apply%s\n' "$c_warn" "$_DH_LIMINE_CONF" "$c_off"
    else
      printf '  cmdline:    %sdrm.edid_firmware NOT on kernel cmdline%s\n' "$c_warn" "$c_off"
    fi
  fi

  if [[ -e /sys/class/drm/card0-eDP-1/edid ]]; then
    local sz
    sz=$(stat -c%s /sys/class/drm/card0-eDP-1/edid 2>/dev/null)
    if (( sz >= 128 )); then
      printf '  EDID sysfs: %s%d bytes (xe driver sees panel)%s\n' "$c_ok" "$sz" "$c_off"
    else
      printf '  EDID sysfs: %s%d bytes (xe failed to read; firmware override required)%s\n' "$c_warn" "$sz" "$c_off"
    fi
  fi

  # Sanity-check that EDID is in the running initramfs — early KMS can't
  # see anything outside the cpio archive.
  local running_initramfs
  running_initramfs="/boot/initramfs-linux-$(uname -r | sed 's/-[0-9]*-cachyos.*//;s/-cachyos.*//').img"
  if [[ -f "$running_initramfs" ]] && command -v lsinitcpio >/dev/null 2>&1; then
    if lsinitcpio "$running_initramfs" 2>/dev/null | grep -q 'edid/asus-b9406'; then
      printf '  initramfs:  %sEDID embedded in current initramfs%s\n' "$c_ok" "$c_off"
    else
      printf '  initramfs:  %sEDID NOT embedded — run %ssudo mkinitcpio -P%s and reboot%s\n' "$c_warn" "$c_dim" "$c_warn" "$c_off"
    fi
  fi

  if command -v kscreen-doctor >/dev/null 2>&1; then
    local hdr_state wcg_state
    hdr_state="$(kscreen-doctor -o 2>/dev/null | awk '/^[[:space:]]+HDR:/ {print $2; exit}')"
    wcg_state="$(kscreen-doctor -o 2>/dev/null | awk '/^[[:space:]]+Wide Color Gamut:/ {print $4; exit}')"
    case "$hdr_state" in
      capable|enabled) printf '  KDE HDR:    %s%s%s\n' "$c_ok" "$hdr_state" "$c_off" ;;
      incapable)       printf '  KDE HDR:    %sincapable (panel EDID still missing)%s\n' "$c_warn" "$c_off" ;;
      *)               [[ -n "$hdr_state" ]] && printf '  KDE HDR:    %s%s%s\n' "$c_dim" "$hdr_state" "$c_off" ;;
    esac
    case "$wcg_state" in
      capable|enabled) printf '  KDE WCG:    %s%s%s\n' "$c_ok" "$wcg_state" "$c_off" ;;
      incapable)       printf '  KDE WCG:    %sincapable%s\n' "$c_warn" "$c_off" ;;
      *)               [[ -n "$wcg_state" ]] && printf '  KDE WCG:    %s%s%s\n' "$c_dim" "$wcg_state" "$c_off" ;;
    esac
  fi
}
