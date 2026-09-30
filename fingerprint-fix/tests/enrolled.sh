#!/usr/bin/env bash
# fp_enrolled_state must not treat "no fingers enrolled" as enrolled.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source ./module.sh

fail=0
check() {
  local name="$1" expected="$2" text="$3" rc="${4:-0}" got
  fprintd-list() { printf '%s\n' "$text"; return "$rc"; }
  got="$(fp_enrolled_state)"
  if [[ $got == "$expected" ]]; then
    printf 'ok  %s\n' "$name"
  else
    printf 'FAIL %s: got %s, expected %s\n' "$name" "$got" "$expected" >&2
    fail=1
  fi
}

check none none "User argrig has no fingers enrolled for Focaltech MOC Sensors."
check positive yes "$(printf '%s\n' \
  'User argrig has 1 finger enrolled for Focaltech MOC Sensors.' \
  ' - #0: right-index-finger')"
check empty unknown ""
check command-failed unknown "has no fingers enrolled" 1

unset -f fprintd-list
if [[ -x /usr/bin/fprintd-list ]]; then
  got="$(fp_enrolled_state)"
  case "$got" in
    yes|none) printf 'ok  live fprintd-list -> %s\n' "$got" ;;
    *) printf 'FAIL live fprintd-list -> %s\n' "$got" >&2; fail=1 ;;
  esac
fi

exit "$fail"
