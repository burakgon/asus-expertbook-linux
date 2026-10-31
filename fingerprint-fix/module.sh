# shellcheck shell=bash
# fingerprint-fix module manifest.
#
# The FocalTech FT9349 fingerprint sensor (USB 2808:a97a) works with stock
# libfprint, driver "Focaltech MOC Sensors" (focaltech_moc): enroll and verify
# need no driver change. After suspend or hibernate, though, fprintd cannot
# open it again:
#
#   failed to claim device: GDBus.Error:net.reactivated.Fprint.Error.Internal:
#   Open failed with error: The device has already been opened!
#
# fprintd keeps the device claimed across sleep, and `systemctl restart
# fprintd` recovers it. The module installs fprintd (not installed by default
# on Arch/CachyOS; libfprint comes with it) and a systemd-sleep hook that
# stops fprintd before sleep and restarts it after resume. It changes no
# driver. Uninstall removes the hook and leaves the package, like
# intel-perf-fix does with thermald.
#
# Package calls go through lib/distro.sh; the package is "fprintd" on both
# pacman and apt systems.

MODULE_NAME="fingerprint-fix"
MODULE_DESC="FocalTech FT9349 fingerprint: reopen fprintd after suspend/hibernate"
MODULE_VERSION="1.0.0"

FP_HOOK=/usr/lib/systemd/system-sleep/fprintd-reset

MODULE_FILES=(
  "fprintd-reset:$FP_HOOK"
)

module_post_install() {
  # mod_install_files copies every payload as 0644; systemd-sleep runs only
  # executable hooks.
  chmod 0755 "$FP_HOOK"

  # pipefail carries a package failure through tail.
  echo "  installing fprintd"
  pkg_install fprintd 2>&1 | tail -3 ||
    die "[fingerprint-fix] could not install fprintd"

  echo
  echo "  Takes effect from the next suspend; no reboot needed."
  echo "  Enroll a finger with: fprintd-enroll"
}

module_post_uninstall() {
  echo
  echo "  fprintd left installed, so enrolled fingerprints keep working."
  echo "  Remove it with:"
  echo "    $(pkg_remove_hint fprintd)"
}

module_status_extra() {
  local user version out name

  if [[ -x $FP_HOOK ]]; then
    printf '  hook:     %sexecutable%s\n' "$c_ok" "$c_off"
  elif [[ -e $FP_HOOK ]]; then
    printf '  hook:     %snot executable, systemd-sleep skips it; run install again%s\n' \
      "$c_warn" "$c_off"
  else
    printf '  hook:     %snot installed%s\n' "$c_warn" "$c_off"
  fi

  if ! command -v fprintd-list >/dev/null 2>&1; then
    if [[ -e $FP_HOOK ]]; then
      printf '  fprintd:  %snot installed; run install again to add it%s\n' "$c_warn" "$c_off"
    else
      printf '  fprintd:  %snot installed; not applicable%s\n' "$c_dim" "$c_off"
    fi
    return 0
  fi
  version="$(pkg_version fprintd)"
  printf '  fprintd:  %s%s%s\n' "$c_ok" "${version:-installed}" "$c_off"

  # status runs without sudo, but list the invoking user's prints under sudo too.
  user="${SUDO_USER:-${USER:-$(id -un)}}"
  out="$(timeout 10 fprintd-list "$user" 2>&1 || true)"
  if grep -q '^found [1-9]' <<<"$out"; then
    name="$(sed -n 's/^Fingerprints for user .* on \(.*\) ([^)]*):$/\1/p; s/^User .* has no fingers enrolled for \(.*\)\.$/\1/p' <<<"$out" | head -n1)"
    printf '  sensor:   %s%s%s (%s enrolled for %s)\n' "$c_ok" "${name:-found}" "$c_off" \
      "$(grep -c '^ - #' <<<"$out")" "$user"
  elif grep -q -i 'no devices available\|found 0 devices' <<<"$out"; then
    printf '  sensor:   %sno fingerprint reader found; not applicable%s\n' "$c_dim" "$c_off"
  else
    printf '  sensor:   %sfprintd-list failed: %s%s\n' "$c_warn" "$(head -n1 <<<"$out")" "$c_off"
  fi
}
