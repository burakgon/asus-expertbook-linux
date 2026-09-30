# fingerprint-fix module manifest. Sourced by ../patch.sh.

MODULE_NAME="fingerprint-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) FocalTech FT9349 fingerprint autosuspend fix"
MODULE_VERSION="1.1.0"

MODULE_FILES=(
  "61-fingerprint-no-autosuspend.hwdb:/etc/udev/hwdb.d/61-fingerprint-no-autosuspend.hwdb"
  "61-fingerprint-no-autosuspend.rules:/etc/udev/rules.d/61-fingerprint-no-autosuspend.rules"
)

# Print the sysfs directory of USB 2808:a97a, or return 1 when it is absent.
fp_device() {
  local d vendor product
  for d in /sys/bus/usb/devices/*; do
    [[ -r $d/idVendor && -r $d/idProduct ]] || continue
    vendor="$(<"$d/idVendor")"
    product="$(<"$d/idProduct")"
    if [[ $vendor == 2808 && $product == a97a ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 1
}

# yes, none, or unknown. "no fingers enrolled" contains the word finger, so a
# substring search for finger cannot be used.
fp_enrolled_state() {
  local user="${SUDO_USER:-$USER}" prints
  if ! command -v fprintd-list >/dev/null 2>&1; then
    printf 'unknown\n'
    return 0
  fi
  if ! prints="$(fprintd-list "$user" 2>/dev/null)"; then
    printf 'unknown\n'
    return 0
  fi
  if [[ $prints == *"has no fingers enrolled"* ]]; then
    printf 'none\n'
  elif [[ $prints == *"enrolled for"* ]]; then
    printf 'yes\n'
  else
    printf 'unknown\n'
  fi
}

fp_reload_udev() {
  systemd-hwdb update
  udevadm control --reload
  udevadm trigger --action=add --subsystem-match=usb \
    --attr-match=idVendor=2808 --attr-match=idProduct=a97a
  udevadm settle --timeout=3
}

# control=auto only allows autosuspend. A negative autosuspend_delay_ms, as
# with usbcore.autosuspend=-1, leaves the device active.
fp_describe_power() {
  local dev="$1" control="" delay="" runtime=""
  [[ -r $dev/power/control ]] && control="$(<"$dev/power/control")"
  [[ -r $dev/power/autosuspend_delay_ms ]] && delay="$(<"$dev/power/autosuspend_delay_ms")"
  [[ -r $dev/power/runtime_status ]] && runtime="$(<"$dev/power/runtime_status")"

  printf '  power:    control=%s delay_ms=%s runtime=%s\n' \
    "${control:-unknown}" "${delay:-unknown}" "${runtime:-unknown}"

  if [[ $control == on ]]; then
    printf '            %sautosuspend is off (control=on)%s\n' "$c_ok" "$c_off"
  elif [[ $delay == -* ]]; then
    printf '            %scontrol=%s, but delay %s disables autosuspend; runtime=%s%s\n' \
      "$c_ok" "$control" "$delay" "$runtime" "$c_off"
  elif [[ $runtime == suspended ]]; then
    printf '            %sreader is suspended; a scan can hang until it is resumed%s\n' \
      "$c_warn" "$c_off"
  else
    printf '            %sautosuspend is allowed; a scan can hang if the reader suspends%s\n' \
      "$c_warn" "$c_off"
  fi
}

module_post_install() {
  local dev control
  fp_reload_udev

  if ! dev="$(fp_device)"; then
    echo "FocalTech FT9349 (2808:a97a) is not present."
    echo "The rule applies the next time the reader is added."
    return 0
  fi

  control="$(<"$dev/power/control")"
  if [[ $control != on ]]; then
    echo "power/control is '$control' on $(basename "$dev"); expected on." >&2
    return 1
  fi

  echo "Autosuspend disabled for FocalTech FT9349 ($(basename "$dev"), control=on)."
  echo "Sensor is integrated into the keyboard power button (top-right key)."
  echo "Enroll with: fprintd-enroll"
}

module_post_uninstall() {
  local dev control
  fp_reload_udev

  if ! dev="$(fp_device)"; then
    echo "FocalTech FT9349 is not present."
    echo "power/control is unchanged until the reader is added again."
    return 0
  fi

  # Removing the rule does not rewrite power/control on an already-bound device.
  printf 'auto\n' >"$dev/power/control"
  control="$(<"$dev/power/control")"
  echo "Set power/control=$control on $(basename "$dev")."
  echo "A replug is not required. Upstream hwdb may autosuspend the reader again."
}

module_status_extra() {
  local dev="" user="${SUDO_USER:-$USER}" enrolled

  if ! dev="$(fp_device)"; then
    printf '  device:   %sno FocalTech FT9349 (2808:a97a) detected%s\n' "$c_warn" "$c_off"
    return 0
  fi
  printf '  device:   FocalTech FT9349 ESS (%s)\n' "$(basename "$dev")"
  fp_describe_power "$dev"

  enrolled="$(fp_enrolled_state)"
  case "$enrolled" in
    yes)     printf '  enrolled: %syes (%s)%s\n' "$c_ok" "$user" "$c_off" ;;
    none)    printf '  enrolled: %snone for %s (run fprintd-enroll)%s\n' "$c_dim" "$user" "$c_off" ;;
    unknown) printf '  enrolled: %scannot tell for %s%s\n' "$c_warn" "$user" "$c_off" ;;
  esac
}
