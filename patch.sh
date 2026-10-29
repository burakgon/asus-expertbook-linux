#!/usr/bin/env bash
# Unified module patcher for asus_expertboot_linux.
#
# Each subfolder containing a `module.sh` is a module. The module manifest
# declares files to install + optional pre/post hooks. This patcher script
# discovers, installs, uninstalls, and reports on those modules.
#
# Usage:
#   ./patch.sh                            # interactive menu (default)
#   ./patch.sh list                       # list available modules + status
#   ./patch.sh install   <module>...      # install (or update) one or more modules
#   ./patch.sh update    <module>...      # alias for install (idempotent)
#   ./patch.sh uninstall <module>...      # uninstall one or more modules
#   ./patch.sh status    [<module>...]    # show install/runtime status
#   ./patch.sh diff      [<module>...]    # show diff between source and installed
#   ./patch.sh install-all                # install every module
#   ./patch.sh update-all                 # update every module currently installed
#   ./patch.sh uninstall-all              # uninstall every module
#
# Module manifest format (module.sh): see ./touchpad-fix/module.sh as the
# canonical example.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
STATE_DIR="/var/lib/asus_expertboot_patcher"

if [[ -t 1 ]]; then
  c_ok=$'\033[32m'; c_err=$'\033[31m'; c_warn=$'\033[33m'
  c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
else
  c_ok=""; c_err=""; c_warn=""; c_dim=""; c_bold=""; c_off=""
fi

log()  { printf '%s* %s%s\n' "$c_dim" "$*" "$c_off"; }
ok()   { printf '%sOK%s   %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%sWARN%s %s\n' "$c_warn" "$c_off" "$*"; }
die()  { printf '%sERR%s  %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

# Platform abstraction: package manager, kernel headers, initramfs, bootloader
# cmdline, services. Sourced before any module is loaded so every module.sh can
# call these helpers via the `with_module` subshell. lib/ contains no module.sh,
# so discover_modules never mistakes it for a module.
if [[ -f "$ROOT_DIR/lib/distro.sh" ]]; then
  # shellcheck source=lib/distro.sh
  source "$ROOT_DIR/lib/distro.sh"
else
  die "missing $ROOT_DIR/lib/distro.sh"
fi

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log "re-executing under sudo"
    exec sudo --preserve-env=PATH -- bash "${BASH_SOURCE[0]}" "$@"
  fi
}

# discover_modules: prints one module folder name per line.
discover_modules() {
  local d
  for d in "$ROOT_DIR"/*/; do
    [[ -f "$d/module.sh" ]] && basename "$d"
  done
}

# with_module <module-name> <function> [args...]
# Sources the module manifest in a subshell and invokes the function. The
# subshell inherits all functions/vars defined in this script, so module hook
# helpers like mod_install_files work.
with_module() {
  local mod="$1"; shift
  local mod_dir="$ROOT_DIR/$mod"
  [[ -d $mod_dir ]] || die "no such module folder: $mod_dir"
  [[ -f "$mod_dir/module.sh" ]] || die "$mod missing module.sh"
  (
    cd "$mod_dir"
    MODULE_DIR="$mod_dir"
    MODULE_NAME="$mod"
    MODULE_DESC=""
    MODULE_VERSION="0"
    MODULE_FILES=()
    # shellcheck source=/dev/null
    source "$mod_dir/module.sh"
    "$@"
  )
}

# Per-module version state. The state file lives under $STATE_DIR and contains
# the version that was current at install time. Empty/missing means "not
# tracked" (either never installed via this script, or installed before
# versioning was introduced).
mod_state_file() {
  printf '%s/%s.version' "$STATE_DIR" "$MODULE_NAME"
}

mod_get_installed_version() {
  local sf
  sf="$(mod_state_file)"
  [[ -f $sf ]] && head -n1 "$sf" || true
}

mod_set_installed_version() {
  install -d -m 0755 "$STATE_DIR"
  printf '%s\n' "${MODULE_VERSION:-0}" > "$(mod_state_file)"
}

mod_clear_installed_version() {
  rm -f -- "$(mod_state_file)"
}

# echoes one of: not-installed | up-to-date | update-available | untracked | partial
mod_install_state() {
  local files installed
  if declare -F module_install_state >/dev/null; then
    module_install_state
    return
  fi
  files="$(mod_files_state)"
  installed="$(mod_get_installed_version)"
  case "$files" in
    none) echo not-installed; return ;;
    some) echo partial; return ;;
  esac
  if [[ -z $installed ]]; then
    echo untracked
  elif [[ $installed == "${MODULE_VERSION:-0}" ]]; then
    echo up-to-date
  else
    echo update-available
  fi
}

mod_install_files() {
  local entry src dst
  for entry in "${MODULE_FILES[@]}"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    [[ -f $src ]] || die "[$MODULE_NAME] missing source file: $src"
    log "[$MODULE_NAME] installing -> $dst"
    install -D -m 0644 "$src" "$dst"
  done
}

# Returns 1 when none of the files existed. A file that exists but cannot be
# removed stops the uninstall (die), so its receipt stays in place.
mod_remove_files() {
  local entry dst removed=0
  for entry in "${MODULE_FILES[@]}"; do
    dst="${entry#*:}"
    if [[ -e $dst || -L $dst ]]; then
      log "[$MODULE_NAME] removing $dst"
      rm -- "$dst" || die "[$MODULE_NAME] cannot remove $dst"
      removed=1
    else
      log "[$MODULE_NAME] not present: $dst"
    fi
  done
  return $(( removed ? 0 : 1 ))
}

# echoes "all" / "some" / "none"
# An empty MODULE_FILES is treated as "all" (vacuously installed) — used by
# hook-only modules whose payload is package installs, not files.
mod_files_state() {
  local entry dst found=0 total=0
  for entry in "${MODULE_FILES[@]:-}"; do
    [[ -z $entry ]] && continue
    dst="${entry#*:}"
    total=$(( total + 1 ))
    [[ -e $dst ]] && found=$(( found + 1 ))
  done
  if   (( total == 0 ));     then echo all
  elif (( found == 0 ));     then echo none
  elif (( found == total )); then echo all
  else echo some
  fi
}

# run_errexit <command> [args...]
# Runs the command in a subshell with errexit in force and returns its status.
# `cmd || rc=$?` or `cmd || true` would not do: bash ignores `set -e` inside
# any function called from a || list, so a failed step would carry on to "OK"
# and a recorded version. Call this as a plain command, never in a condition.
run_errexit() {
  set +e
  ( set -e; "$@" )
  RUN_ERREXIT_RC=$?
  set -e
}

# Menu actions keep going after a module fails, with errexit intact inside.
menu_try() {
  local what="$1"
  if [[ $1 == with_module ]]; then
    what="[$2] ${3#do_}"; what="${what%_one}"
  fi
  run_errexit "$@"
  if (( RUN_ERREXIT_RC != 0 )); then
    warn "$what failed (exit $RUN_ERREXIT_RC)"
  fi
}

# Per-module operation wrappers (invoked inside `with_module` subshell).

do_install_one() {
  local prev rc=0
  prev="$(mod_get_installed_version)"

  if declare -F module_install >/dev/null; then
    run_errexit module_install
    rc=$RUN_ERREXIT_RC
    if (( rc == 10 )); then
      warn "[$MODULE_NAME] skipped"
      return 0
    elif (( rc != 0 )); then
      return "$rc"
    fi
  else
    mod_install_files
    if declare -F module_post_install >/dev/null; then
      module_post_install
    fi
  fi

  mod_set_installed_version
  if [[ -z $prev ]]; then
    printf '%sOK%s   [%s] installed v%s\n' "$c_ok" "$c_off" \
      "$MODULE_NAME" "${MODULE_VERSION:-0}"
  elif [[ $prev == "${MODULE_VERSION:-0}" ]]; then
    printf '%sOK%s   [%s] reinstalled v%s (no version change)\n' \
      "$c_ok" "$c_off" "$MODULE_NAME" "${MODULE_VERSION:-0}"
  else
    printf '%sOK%s   [%s] updated v%s -> v%s\n' "$c_ok" "$c_off" \
      "$MODULE_NAME" "$prev" "${MODULE_VERSION:-0}"
  fi
}

do_uninstall_one() {
  local had_payload=0 prev
  prev="$(mod_get_installed_version)"
  if mod_remove_files; then
    had_payload=1
  fi

  # Hook-only modules have no MODULE_FILES to remove. Run their teardown only
  # when a state file proves the patcher previously installed them.
  if (( had_payload )) || [[ -n $prev ]]; then
    if declare -F module_post_uninstall >/dev/null; then
      module_post_uninstall
    fi
    mod_clear_installed_version
    printf '%sOK%s   [%s] uninstalled\n' "$c_ok" "$c_off" "$MODULE_NAME"
  else
    mod_clear_installed_version
    printf '%sOK%s   [%s] nothing to remove\n' "$c_ok" "$c_off" "$MODULE_NAME"
  fi
}

do_list_one() {
  _table_row "$@"
}

# Column widths (visible chars only — color codes wrap padded text).
_TBL_W_IDX=3
_TBL_W_NAME=25
_TBL_W_CUR=10
_TBL_W_INSTALLED=10
_TBL_W_STATE=14
_TBL_GUTTER=2  # spaces between columns

_table_max_desc_width() {
  local cols fixed
  cols=$(tput cols 2>/dev/null || echo 100)
  fixed=$(( _TBL_W_IDX + _TBL_W_NAME + _TBL_W_CUR + _TBL_W_INSTALLED + _TBL_W_STATE + 5 * _TBL_GUTTER + 2 ))
  local avail=$(( cols - fixed ))
  (( avail < 20 )) && avail=20
  printf '%s' "$avail"
}

_table_truncate() {
  local s="$1" n="$2"
  if (( ${#s} > n )); then
    printf '%s…' "${s:0:$((n-1))}"
  else
    printf '%s' "$s"
  fi
}

_table_header() {
  local desc_w h_idx="#" h_name="Module" h_cur="Version" h_inst="Installed" h_state="State" h_desc="Description"
  desc_w="$(_table_max_desc_width)"
  printf '  %s%-*s %-*s %-*s %-*s %-*s %-*s%s\n' \
    "$c_bold" \
    "$_TBL_W_IDX"       "$h_idx" \
    "$_TBL_W_NAME"      "$h_name" \
    "$_TBL_W_CUR"       "$h_cur" \
    "$_TBL_W_INSTALLED" "$h_inst" \
    "$_TBL_W_STATE"     "$h_state" \
    "$desc_w"           "$h_desc" \
    "$c_off"
  local rule_w=$(( _TBL_W_IDX + _TBL_W_NAME + _TBL_W_CUR + _TBL_W_INSTALLED + _TBL_W_STATE + desc_w + 5 ))
  local rule
  printf -v rule '%*s' "$rule_w" ''
  printf '  %s%s%s\n' "$c_dim" "${rule// /-}" "$c_off"
}

# _table_row [index]
# Reads MODULE_NAME / MODULE_DESC / MODULE_VERSION from the current scope.
_table_row() {
  local idx="${1:-}" state installed cur color label desc desc_w
  state="$(mod_install_state)"
  installed="$(mod_get_installed_version)"
  cur="${MODULE_VERSION:-0}"
  # Runtime-managed modules (for example UEFI firmware) can determine that the
  # target version is already present without having a patcher state file.
  if [[ -z $installed && $state == up-to-date ]] && \
     declare -F module_install_state >/dev/null; then
    installed="$cur"
  fi
  case "$state" in
    up-to-date)       color="$c_ok";   label="up to date" ;;
    update-available) color="$c_warn"; label="update avail" ;;
    untracked)        color="$c_warn"; label="untracked" ;;
    partial)          color="$c_warn"; label="partial" ;;
    not-installed)    color="$c_dim";  label="not installed" ;;
  esac
  desc_w="$(_table_max_desc_width)"
  desc="$(_table_truncate "${MODULE_DESC:-}" "$desc_w")"

  # Pad state to its column width *before* wrapping in color so alignment holds.
  local state_padded
  printf -v state_padded '%-*s' "$_TBL_W_STATE" "$label"

  printf '  %-*s %-*s %-*s %-*s %s%s%s %-*s\n' \
    "$_TBL_W_IDX"       "${idx:--}" \
    "$_TBL_W_NAME"      "$MODULE_NAME" \
    "$_TBL_W_CUR"       "$cur" \
    "$_TBL_W_INSTALLED" "${installed:--}" \
    "$color" "$state_padded" "$c_off" \
    "$desc_w" "$desc"
}

do_diff_one() {
  local entry src dst any=0
  printf '%s%s%s\n' "$c_bold" "$MODULE_NAME" "$c_off"
  for entry in "${MODULE_FILES[@]}"; do
    src="${entry%%:*}"; dst="${entry#*:}"
    if [[ ! -e $dst ]]; then
      printf '  %s+ would create%s %s\n' "$c_warn" "$c_off" "$dst"
      any=1
      continue
    fi
    if cmp -s "$src" "$dst"; then
      printf '  %s= unchanged%s    %s\n' "$c_dim" "$c_off" "$dst"
    else
      printf '  %s~ would update%s %s\n' "$c_warn" "$c_off" "$dst"
      # diff returns 1 when files differ — that's the expected case here, so
      # swallow it explicitly instead of letting `set -e` abort.
      diff -u "$dst" "$src" 2>/dev/null \
        | sed -e "s|^--- .*|--- a/$dst (installed)|" \
              -e "s|^+++ .*|+++ b/$src (source)|" \
              -e 's/^/    /' \
        || true
      any=1
    fi
  done
  (( any )) || printf '  %sup to date%s\n' "$c_ok" "$c_off"
  echo
}

do_status_one() {
  local entry src dst installed cur state version_line file_count=0
  installed="$(mod_get_installed_version)"
  cur="${MODULE_VERSION:-0}"
  state="$(mod_install_state)"
  case "$state" in
    up-to-date)       version_line="${c_ok}v${cur} (up to date)${c_off}" ;;
    update-available) version_line="${c_warn}v${installed} installed; v${cur} available — run install/update${c_off}" ;;
    untracked)        version_line="${c_warn}files present but not tracked; run install to record v${cur}${c_off}" ;;
    partial)          version_line="${c_warn}partial install (some files missing)${c_off}" ;;
    not-installed)    version_line="${c_dim}not installed (v${cur} available)${c_off}" ;;
  esac
  printf '%s%s%s — %s\n' "$c_bold" "$MODULE_NAME" "$c_off" "${MODULE_DESC:-}"
  printf '  version:  %s\n' "$version_line"
  printf '  files:\n'
  for entry in "${MODULE_FILES[@]}"; do
    file_count=$(( file_count + 1 ))
    src="${entry%%:*}"; dst="${entry#*:}"
    if [[ -e $dst ]]; then
      printf '    %sOK%s   %s\n' "$c_ok" "$c_off" "$dst"
    else
      printf '    %s--%s   %s (not installed)\n' "$c_dim" "$c_off" "$dst"
    fi
  done
  if (( file_count == 0 )); then
    printf '    %s(runtime-managed module; see status below)%s\n' "$c_dim" "$c_off"
  fi
  declare -F module_status_extra >/dev/null && module_status_extra || true
  echo
}

# run_each <do_fn> <module>... -- run the per-module operation on every named
# module, with errexit in force inside each, and carry on past a failure so
# one broken module does not hold back the rest. Fails at the end if any did.
run_each() {
  local fn="$1" m
  local -a failed=()
  shift
  # A mistyped name stops the run before anything is changed.
  for m in "$@"; do
    [[ -f $ROOT_DIR/$m/module.sh ]] || die "no such module: $m (try: list)"
  done
  for m in "$@"; do
    run_errexit with_module "$m" "$fn"
    (( RUN_ERREXIT_RC == 0 )) || failed+=("$m")
  done
  (( ${#failed[@]} == 0 )) ||
    die "failed: ${failed[*]} ($(( $# - ${#failed[@]} )) of $# modules went through; see the errors above)"
}

cmd_install() {
  require_root install "$@"
  (( $# > 0 )) || die "install: at least one module name required (try: list)"
  run_each do_install_one "$@"
}

cmd_uninstall() {
  require_root uninstall "$@"
  (( $# > 0 )) || die "uninstall: at least one module name required"
  run_each do_uninstall_one "$@"
}

cmd_install_all() {
  require_root install-all
  local mods=()
  while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)
  (( ${#mods[@]} > 0 )) || die "no modules found in $ROOT_DIR"
  cmd_install "${mods[@]}"
}

cmd_diff() {
  local mods=("$@")
  if (( ${#mods[@]} == 0 )); then
    mods=()
    while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)
  fi
  (( ${#mods[@]} > 0 )) || die "no modules found"
  local m
  for m in "${mods[@]}"; do with_module "$m" do_diff_one; done
}

# update-all: re-install installed modules whose recorded version differs from
# the current module version. Skips up-to-date and never-installed modules.
cmd_update_all() {
  require_root update-all
  local mods=() to_update=() m state
  while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)
  (( ${#mods[@]} > 0 )) || die "no modules found in $ROOT_DIR"

  for m in "${mods[@]}"; do
    state="$(with_module "$m" mod_install_state)"
    case "$state" in
      update-available|untracked|partial) to_update+=("$m") ;;
    esac
  done

  if (( ${#to_update[@]} == 0 )); then
    ok "all installed modules are up to date"
    return 0
  fi
  log "modules to update: ${to_update[*]}"
  cmd_install "${to_update[@]}"
}

cmd_uninstall_all() {
  require_root uninstall-all
  local mods=()
  while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)
  (( ${#mods[@]} > 0 )) || die "no modules found in $ROOT_DIR"
  cmd_uninstall "${mods[@]}"
}

cmd_list() {
  printf '%sModules in %s%s\n\n' "$c_bold" "$ROOT_DIR" "$c_off"
  _table_header
  local m count=0 i=1
  while IFS= read -r m; do
    with_module "$m" _table_row "$i"
    count=$(( count + 1 ))
    i=$(( i + 1 ))
  done < <(discover_modules)
  (( count > 0 )) || warn "no modules found"
}

cmd_status() {
  local mods=("$@")
  if (( ${#mods[@]} == 0 )); then
    mods=()
    while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)
  fi
  (( ${#mods[@]} > 0 )) || die "no modules found"
  local m
  for m in "${mods[@]}"; do with_module "$m" do_status_one; done
}

cmd_menu() {
  require_root menu
  local -a mods
  local choice action arg m i
  while true; do
    mods=()
    while IFS= read -r m; do mods+=("$m"); done < <(discover_modules)

    clear 2>/dev/null || true
    printf '%s=== asus_expertboot_linux patcher ===%s\n\n' "$c_bold" "$c_off"

    if (( ${#mods[@]} == 0 )); then
      warn "no modules found in $ROOT_DIR"
    else
      _table_header
      for i in "${!mods[@]}"; do
        with_module "${mods[$i]}" _table_row "$(( i + 1 ))"
      done
    fi

    cat <<EOF

${c_bold}Actions${c_off}
  i <num>    install / update module (idempotent — re-runs post hooks)
  u <num>    uninstall module
  d <num>    diff source vs installed (omit num for all)
  s <num>    detailed status (omit num for all modules)
  I          install all modules
  up         update all currently-installed modules
  U          uninstall all modules
  r          refresh
  q          quit
EOF
    printf '\n> '
    if ! IFS= read -r choice; then
      echo; return 0
    fi

    # split into action + first arg
    action="${choice%% *}"
    arg=""
    [[ $choice == *' '* ]] && arg="${choice#* }"
    arg="${arg// /}"  # strip whitespace from numeric arg

    case "$action" in
      q|quit|exit) return 0 ;;
      ""|r|refresh) ;;
      i|install|update)
        m=$(_menu_resolve_index "$arg" "${mods[@]:-}") || { _menu_pause; continue; }
        menu_try with_module "$m" do_install_one
        _menu_pause
        ;;
      u|uninstall|remove)
        m=$(_menu_resolve_index "$arg" "${mods[@]:-}") || { _menu_pause; continue; }
        menu_try with_module "$m" do_uninstall_one
        _menu_pause
        ;;
      d|diff)
        if [[ -z $arg ]]; then
          for m in "${mods[@]}"; do with_module "$m" do_diff_one || true; done
        else
          m=$(_menu_resolve_index "$arg" "${mods[@]:-}") || { _menu_pause; continue; }
          with_module "$m" do_diff_one || true
        fi
        _menu_pause
        ;;
      s|status|check)
        if [[ -z $arg ]]; then
          for m in "${mods[@]}"; do with_module "$m" do_status_one || true; done
        else
          m=$(_menu_resolve_index "$arg" "${mods[@]:-}") || { _menu_pause; continue; }
          with_module "$m" do_status_one || true
        fi
        _menu_pause
        ;;
      I|install-all)
        for m in "${mods[@]}"; do menu_try with_module "$m" do_install_one; done
        _menu_pause
        ;;
      up|update-all)
        menu_try cmd_update_all
        _menu_pause
        ;;
      U|uninstall-all)
        for m in "${mods[@]}"; do menu_try with_module "$m" do_uninstall_one; done
        _menu_pause
        ;;
      l|list)
        for m in "${mods[@]}"; do with_module "$m" do_status_one || true; done
        _menu_pause
        ;;
      *)
        warn "unknown action: $action (try i/u/s/I/U/r/q)"
        _menu_pause
        ;;
    esac
  done
}

# Resolve "1" → first module name, or pass through a name that exists.
# Echoes the module name on success; prints an error and returns 1 otherwise.
_menu_resolve_index() {
  local arg="$1"; shift
  local -a mods=("$@")
  if [[ -z $arg ]]; then
    warn "missing module number"
    return 1
  fi
  if [[ $arg =~ ^[0-9]+$ ]]; then
    local idx=$(( arg - 1 ))
    if (( idx < 0 || idx >= ${#mods[@]} )); then
      warn "no module #$arg (have ${#mods[@]})"
      return 1
    fi
    echo "${mods[$idx]}"
    return 0
  fi
  for m in "${mods[@]}"; do
    [[ $m == "$arg" ]] && { echo "$m"; return 0; }
  done
  warn "unknown module: $arg"
  return 1
}

_menu_pause() {
  printf '\n%spress enter to continue%s' "$c_dim" "$c_off"
  IFS= read -r _ || true
}

main() {
  case "${1:-}" in
    list)              shift; cmd_list          "$@" ;;
    install|update)    shift; cmd_install       "$@" ;;
    uninstall|remove)  shift; cmd_uninstall     "$@" ;;
    install-all)       shift; cmd_install_all   "$@" ;;
    update-all)        shift; cmd_update_all    "$@" ;;
    uninstall-all)     shift; cmd_uninstall_all "$@" ;;
    status|check)      shift; cmd_status        "$@" ;;
    diff)              shift; cmd_diff          "$@" ;;
    menu)              shift; cmd_menu          "$@" ;;
    "")                cmd_menu ;;
    -h|--help)         usage ;;
    *)                 die "unknown command: $1 (try --help)" ;;
  esac
}

main "$@"
