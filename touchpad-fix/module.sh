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
MODULE_VERSION="1.2.1"

# The libinput quirk is the load-bearing fix; the hwdb clamp is optional
# belt-and-suspenders (verified: quirk alone stops the Touch-jumps even with
# pressure max still misreported).
#
# libinput reads admin overrides only from /etc/libinput/local-overrides.quirks
# (other *.quirks files in /etc/libinput are ignored), and that one file is
# shared with every other override on the machine. Up to 1.1.1 this module
# replaced it wholesale. The quirk now lives in a marked block inside it:
# install drops earlier B9406 touchpad sections (the 1.1.x copy and
# Omarchy-derived ones) and keeps every other section; uninstall removes only
# the block.
MODULE_FILES=(
  "61-pixart-4f05-pressure-fix.hwdb:/etc/udev/hwdb.d/61-pixart-4f05-pressure-fix.hwdb"
)

TP_QUIRKS=/etc/libinput/local-overrides.quirks
TP_QUIRK_SRC=99-asus-expertbook-pixart-4f05.quirks
TP_BEGIN="# >>> asus-expertbook-linux touchpad-fix >>>"
TP_END="# <<< asus-expertbook-linux touchpad-fix <<<"
TP_LOCK=/run/asus-expertbook-touchpad-fix.lock

# Print file $1 without our managed block and without earlier B9406 touchpad
# sections. Key lines of a stale section are dropped up to the next [header],
# never left outside a section, which would make libinput reject the whole
# file. Comment and blank lines are held back until the next line decides
# whom they describe: a stale header (dropped with it) or anything else (kept).
_tp_strip() {
  awk -v b="$TP_BEGIN" -v e="$TP_END" '
    function flush() { if (buf != "") printf "%s", buf; buf = "" }
    $0 == b { inblock = 1; buf = ""; next }
    $0 == e { inblock = 0; next }
    inblock { next }
    /^[[:space:]]*(#.*)?$/ { buf = buf $0 "\n"; next }
    /^\[/ {
      if ($0 ~ /^\[ASUS ExpertBook (Ultra )?B9406 Touchpad\]$/) { legacy = 1; buf = ""; next }
      legacy = 0; flush(); print; next
    }
    legacy { buf = ""; next }
    { flush(); print }
    END { if (!legacy) flush() }
  ' "$1"
}

# True when $1 holds anything besides comments and blank lines.
_tp_has_content() {
  grep -qv -E '^[[:space:]]*(#.*)?$' <<<"$1"
}

# The markers must pair up: never nested, never left open. Anything else means
# the file was edited by hand, and stripping would guess at what to delete.
_tp_markers_ok() {
  awk -v b="$TP_BEGIN" -v e="$TP_END" '
    $0 == b { if (open) bad = 1; open = 1 }
    $0 == e { if (!open) bad = 1; open = 0 }
    END { exit (bad || open) }
  ' "$1"
}

# Check a candidate file the way libinput will read it: one bad line (or a
# file with no section at all) makes libinput drop every quirk on the machine.
_tp_validate() {
  local dir rc=0
  libinput quirks --help >/dev/null 2>&1 ||
    die "[touchpad-fix] 'libinput quirks' is needed to check $TP_QUIRKS before replacing it (install the libinput-tools package; on older Arch it is part of libinput)"
  dir="$(mktemp -d)" || return 1
  if ! cp -- "$1" "$dir/local-overrides.quirks" ||
     ! libinput quirks validate --data-dir "$dir"; then
    rc=1
  fi
  rm -rf -- "$dir"
  return "$rc"
}

# Replace the file atomically after validating the new content, keeping the
# previous version next to it as local-overrides.quirks.asus-expertbook-linux.bak.
_tp_write() {
  local content="$1" tmp
  install -d -m 0755 "${TP_QUIRKS%/*}" || return 1
  tmp="$(mktemp "${TP_QUIRKS%/*}/.local-overrides.quirks.XXXXXX")" || return 1
  if ! printf '%s\n' "$content" >"$tmp" || ! chmod 0644 "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! _tp_validate "$tmp"; then
    rm -f -- "$tmp"
    die "[touchpad-fix] the new $TP_QUIRKS would not pass 'libinput quirks validate'; left it unchanged"
  fi
  if [[ -f $TP_QUIRKS ]] && ! cp -a -- "$TP_QUIRKS" "$TP_QUIRKS.asus-expertbook-linux.bak"; then
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$TP_QUIRKS" || { rm -f -- "$tmp"; return 1; }
}

# Print the file with our block and stale B9406 sections removed, refusing to
# guess when the markers are broken.
_tp_rest() {
  _tp_markers_ok "$TP_QUIRKS" ||
    die "[touchpad-fix] $TP_QUIRKS has an unpaired '$TP_BEGIN' or '$TP_END' line; fix it by hand, nothing was changed"
  _tp_strip "$TP_QUIRKS"
}

# Hold the lock for the whole read, validate, back up and replace cycle, so a
# second run of this module cannot lose the first one's edit. It is released
# when the module's subshell exits.
_tp_lock() {
  exec {TP_LOCK_FD}>"$TP_LOCK" || die "[touchpad-fix] cannot open $TP_LOCK"
  flock -w 30 "$TP_LOCK_FD" || die "[touchpad-fix] another run holds $TP_LOCK"
}

_tp_install_quirk() {
  local rest="" src block
  src="$(cat -- "$TP_QUIRK_SRC")" || die "[touchpad-fix] cannot read $TP_QUIRK_SRC"
  grep -q '^\[' <<<"$src" || die "[touchpad-fix] $TP_QUIRK_SRC holds no quirk section"
  _tp_lock
  if [[ -f $TP_QUIRKS ]]; then
    rest="$(_tp_rest)" || exit 1
  fi
  block="$TP_BEGIN"$'\n'"$src"$'\n'"$TP_END"
  if _tp_has_content "$rest"; then
    _tp_write "$rest"$'\n\n'"$block" || die "[touchpad-fix] cannot write $TP_QUIRKS"
  else
    _tp_write "$block" || die "[touchpad-fix] cannot write $TP_QUIRKS"
  fi
  log "[touchpad-fix] quirk block written to $TP_QUIRKS"
}

_tp_remove_quirk() {
  local rest
  [[ -f $TP_QUIRKS ]] || return 0
  _tp_lock
  rest="$(_tp_rest)" || exit 1
  if _tp_has_content "$rest"; then
    _tp_write "$rest" || die "[touchpad-fix] cannot write $TP_QUIRKS"
  else
    # libinput rejects an override file without any section, so remove it.
    if ! cp -a -- "$TP_QUIRKS" "$TP_QUIRKS.asus-expertbook-linux.bak" ||
       ! rm -f -- "$TP_QUIRKS"; then
      die "[touchpad-fix] cannot remove $TP_QUIRKS"
    fi
  fi
}

module_install_state() {
  local files installed block=0
  grep -qxF "$TP_BEGIN" "$TP_QUIRKS" 2>/dev/null && block=1
  files="$(mod_files_state)"
  installed="$(mod_get_installed_version)"
  if [[ -n $installed && $installed != "$MODULE_VERSION" ]]; then
    echo update-available
  elif [[ $files == none ]] && (( ! block )); then
    echo not-installed
  elif [[ $files != all ]] || (( ! block )); then
    echo partial
  elif [[ -z $installed ]]; then
    echo untracked
  else
    echo up-to-date
  fi
}

module_post_install() {
  _tp_install_quirk
  systemd-hwdb update
  udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true
  echo "Reboot required for libinput / compositor to re-open the device."
}

module_post_uninstall() {
  _tp_remove_quirk
  systemd-hwdb update
  udevadm trigger --action=change --subsystem-match=input >/dev/null 2>&1 || true
  udevadm settle --timeout=3 >/dev/null 2>&1 || true
  echo "Reboot to fully restore default touchpad behaviour."
}

module_status_extra() {
  local ev
  if grep -qxF "$TP_BEGIN" "$TP_QUIRKS" 2>/dev/null; then
    printf '  quirk:    %smanaged block in %s%s\n' "$c_ok" "$TP_QUIRKS" "$c_off"
  elif grep -qE '^\[ASUS ExpertBook (Ultra )?B9406 Touchpad\]$' "$TP_QUIRKS" 2>/dev/null; then
    printf '  quirk:    %sunmanaged B9406 section in %s; reinstall to convert it%s\n' \
      "$c_warn" "$TP_QUIRKS" "$c_off"
  else
    printf '  quirk:    %snot present in %s%s\n' "$c_warn" "$TP_QUIRKS" "$c_off"
  fi

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

  # Try the current user's access first (e.g. input group/session ACLs).
  # Requiring EUID=0 hid valid results on machines where this already works.
  local out
  if out="$(libinput quirks list "/dev/input/$ev" 2>/dev/null)"; then
    :
  elif [[ $EUID -ne 0 ]] && sudo -n true 2>/dev/null; then
    out="$(sudo -n libinput quirks list "/dev/input/$ev" 2>/dev/null || true)"
  else
    printf '  libinput: %srun status as root to list the active quirks%s\n' "$c_dim" "$c_off"
    return 0
  fi
  if [[ -z $out ]]; then
    printf '  libinput: %sno quirks active for this device%s\n' "$c_warn" "$c_off"
  else
    printf '  libinput: '
    printf '%s\n' "$out" | sed '1s/^/   /; 2,$s/^/            /' | sed '1s/^   //'
  fi
}
