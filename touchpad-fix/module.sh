# touchpad-fix module manifest. Sourced by ../patch.sh.
#
# Available variables (read by patch.sh):
#   MODULE_NAME    short identifier (defaults to folder name)
#   MODULE_DESC    one-line description
#   MODULE_VERSION version string; bump on every change so patch.sh detects
#                  that an update is available on machines running an older
#                  copy. Defaults to "0" if unset.
#   MODULE_FILES   array of "src_relative_to_module_dir:dst_absolute" entries
#
# Available hooks (optional, defined as shell functions):
#   module_post_install     run after files are copied into place
#   module_post_uninstall   run after files are removed
#   module_status_extra     print extra status info (already inside a section)

MODULE_NAME="touchpad-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) PixArt 093A:4F05 touchpad workaround"
MODULE_VERSION="1.1.0"

# NOTE: libinput 1.31 only honors '/etc/libinput/local-overrides.quirks' for
# admin overrides — arbitrary *.quirks files in that directory are silently
# ignored (only /usr/share/libinput/*.quirks gets globbed). So the source
# file ships with a descriptive name but installs to the canonical name.
MODULE_FILES=(
  "61-pixart-4f05-pressure-fix.hwdb:/etc/udev/hwdb.d/61-pixart-4f05-pressure-fix.hwdb"
  "99-asus-expertbook-pixart-4f05.quirks:/etc/libinput/local-overrides.quirks"
)

module_post_install() {
  systemd-hwdb update
  udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true
  echo "Reboot required for libinput / compositor to re-open the device."
}

module_post_uninstall() {
  systemd-hwdb update
  udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true
  echo "Reboot to fully restore default touchpad behaviour."
}

module_status_extra() {
  local ev
  ev="$(awk '
    /^I:/ { i=$0; n="" }
    /^N:/ { n=$0 }
    /^H:/ {
      if (tolower(i) ~ /vendor=093a/ && tolower(i) ~ /product=4f05/ && n ~ /Touchpad/) {
        if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
      }
    }' /proc/bus/input/devices 2>/dev/null)"
  if [[ -z $ev ]]; then
    printf '  device:   %sno PixArt 093A:4F05 touchpad detected%s\n' "$c_warn" "$c_off"
    return 0
  fi
  printf '  device:   /dev/input/%s\n' "$ev"

  if ! command -v libinput >/dev/null 2>&1; then
    printf '  libinput: %slibinput-tools not installed%s\n' "$c_warn" "$c_off"
    return 0
  fi

  local out
  if [[ $EUID -eq 0 ]]; then
    out="$(libinput quirks list "/dev/input/$ev" 2>/dev/null || true)"
  else
    out="$(sudo -n libinput quirks list "/dev/input/$ev" 2>/dev/null || true)"
  fi
  if [[ -z $out ]]; then
    printf '  libinput: %sno quirks active for this device%s\n' "$c_warn" "$c_off"
  else
    printf '  libinput: '
    printf '%s\n' "$out" | sed '1s/^/   /; 2,$s/^/            /' | sed '1s/^   //'
  fi
}
