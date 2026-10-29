# shellcheck shell=bash
#
# lib/distro.sh -- platform abstraction for patch.sh.
#
# Sourced by patch.sh before any module is loaded. Because `with_module` runs
# each module.sh in a subshell that inherits patch.sh's functions, everything
# defined here is callable from any module.sh without changing the module
# contract (MODULE_NAME / MODULE_FILES / module_* hooks are untouched).
#
# Ground rule: the Arch branch of every function emits exactly the command the
# modules ran before this file existed, in the same order. Behaviour on Arch
# and its derivatives is unchanged; the other branches are additive.
#
# Provided:
#   detection   distro_family
#   packages    pkg_manager pkg_version pkg_installed pkg_available
#               pkg_atleast pkg_install pkg_remove_hint
#   kernel      kernel_list kernel_headers_present kernel_headers_install
#               initramfs_regen
#   boot params cmdline_backend cmdline_active cmdline_active_value
#               cmdline_configured cmdline_add cmdline_remove
#   services    svc_unit svc_exists svc_is_active svc_enable_now
#               svc_disable_now
#
# Overridable for testing (never set in normal use):
#   GRUB_FILE  KERNELSTUB_FILE  LIMINE_DROPIN_DIR  CMDLINE_BACKEND

# ----------------------------------------------------------------- detection

# distro_family -> arch | debian | unknown
#
# Reads ID *and* ID_LIKE. ID alone is not enough: Pop!_OS is `ID=pop
# ID_LIKE="ubuntu debian"`, CachyOS/EndeavourOS/Manjaro are `ID_LIKE=arch`.
distro_family() {
  local id="" id_like="" token
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    id="$( { . /etc/os-release; printf '%s' "${ID:-}"; } 2>/dev/null || true )"
    # shellcheck disable=SC1091
    id_like="$( { . /etc/os-release; printf '%s' "${ID_LIKE:-}"; } 2>/dev/null || true )"
  fi
  # Deliberately unquoted: ID_LIKE is a space-separated list.
  # shellcheck disable=SC2086
  for token in $id $id_like; do
    case "$token" in
      arch)          echo arch;   return 0 ;;
      debian|ubuntu) echo debian; return 0 ;;
    esac
  done
  # No usable os-release (container, minimal chroot): trust what is installed.
  if command -v pacman >/dev/null 2>&1; then
    echo arch
  elif command -v dpkg-query >/dev/null 2>&1; then
    echo debian
  else
    echo unknown
  fi
}

# ------------------------------------------------------------------ packages

# pkg_manager -> pacman | apt | none
pkg_manager() {
  local family
  family="$(distro_family)"
  if [[ $family == arch ]] && command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif [[ $family == debian ]] && command -v dpkg-query >/dev/null 2>&1; then
    echo apt
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v dpkg-query >/dev/null 2>&1; then
    echo apt
  else
    echo none
  fi
}

# pkg_version <pkg> -- installed version, empty when not installed.
pkg_version() {
  local out=""
  case "$(pkg_manager)" in
    pacman)
      out="$(pacman -Q "$1" 2>/dev/null | awk '{print $2}' || true)"
      ;;
    apt)
      # dpkg-query -W also succeeds for removed-but-known packages, so filter
      # on the status field rather than on the exit code.
      out="$(dpkg-query -W -f='${db:Status-Status}\t${Version}' "$1" 2>/dev/null \
             | awk -F'\t' '$1 == "installed" { print $2 }' || true)"
      ;;
  esac
  printf '%s\n' "$out"
}

# pkg_installed <pkg>
pkg_installed() {
  [[ -n "$(pkg_version "$1")" ]]
}

# pkg_available <pkg> -- known to the configured repositories?
pkg_available() {
  local candidate
  case "$(pkg_manager)" in
    pacman)
      pacman -Si "$1" >/dev/null 2>&1
      ;;
    apt)
      # LC_ALL=C: apt-cache policy translates its field labels.
      candidate="$(LC_ALL=C apt-cache policy "$1" 2>/dev/null \
                   | awk '/^ *Candidate:/ { print $2; exit }' || true)"
      [[ -n $candidate && $candidate != "(none)" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# pkg_atleast <pkg> <min-version> -- installed version >= min-version?
#
# Generalises the sort -V comparison audio-fix already used to gate its bundled
# UCM files against alsa-ucm-conf 1.2.16.
pkg_atleast() {
  local have lowest
  have="$(pkg_version "$1")"
  have="${have#*:}"     # drop an epoch  (1:2.5.6 -> 2.5.6)
  have="${have%%-*}"    # drop pkgrel / Debian revision
  [[ -n $have ]] || return 1
  lowest="$(printf '%s\n%s\n' "$2" "$have" | sort -V | sed -n '1p')"
  [[ $lowest == "$2" ]]
}

# pkg_install <pkg>...
pkg_install() {
  (( $# > 0 )) || return 0
  case "$(pkg_manager)" in
    pacman)
      pacman -S --needed --noconfirm "$@"
      ;;
    apt)
      if DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; then
        return 0
      fi
      log "refreshing the package index and retrying"
      DEBIAN_FRONTEND=noninteractive apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
      ;;
    *)
      warn "no supported package manager; install by hand: $*"
      return 1
      ;;
  esac
}

# pkg_remove_hint <pkg>... -- the removal command to print for the user.
pkg_remove_hint() {
  case "$(pkg_manager)" in
    pacman) printf 'sudo pacman -Rns %s\n' "$*" ;;
    apt)    printf 'sudo apt-get purge %s\n' "$*" ;;
    *)      printf 'remove by hand: %s\n'   "$*" ;;
  esac
}

# ------------------------------------------------- kernel headers / initramfs

# kernel_list -- installed kernel release names, one per line.
kernel_list() {
  local dir kver seen=""
  for dir in /usr/lib/modules/*/ /lib/modules/*/; do
    [[ -d $dir ]] || continue
    kver="${dir%/}"; kver="${kver##*/}"
    # /lib/modules and /usr/lib/modules are the same tree on merged-usr systems.
    case " $seen " in *" $kver "*) continue ;; esac
    seen="$seen $kver"
    printf '%s\n' "$kver"
  done
}

# kernel_headers_present [kernel-release]
kernel_headers_present() {
  local kver="${1:-$(uname -r)}"
  [[ -e "/usr/lib/modules/$kver/build/Makefile" ]] ||
    [[ -e "/lib/modules/$kver/build/Makefile" ]]
}

# kernel_headers_install [kernel-release]
#
# Arch keeps the source package name in /lib/modules/<kver>/pkgbase, so the
# headers package is "<pkgbase>-headers" -- the same lookup audio-fix did
# inline. Debian names them linux-headers-<kver> directly.
kernel_headers_install() {
  local kver="${1:-$(uname -r)}" package=""
  kernel_headers_present "$kver" && return 0
  case "$(pkg_manager)" in
    pacman)
      if [[ -r /lib/modules/$kver/pkgbase ]]; then
        package="$(<"/lib/modules/$kver/pkgbase")-headers"
      fi
      ;;
    apt)
      package="linux-headers-$kver"
      ;;
  esac
  if [[ -z $package ]]; then
    warn "cannot map kernel $kver to a headers package"
    return 1
  fi
  log "installing kernel headers for $kver: $package"
  pkg_install "$package" || return 1
  kernel_headers_present "$kver"
}

# initramfs_regen [reason]
#
# Arch order (limine-mkinitcpio, then mkinitcpio -P) is preserved, so this is a
# drop-in for audio-fix's audio_refresh_initramfs. A system with no generator
# at all is reported but not treated as an error, matching the previous
# silent no-op.
initramfs_regen() {
  local reason="${1:-after the change}"
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    log "rebuilding Limine initramfs entries $reason"
    limine-mkinitcpio
  elif command -v mkinitcpio >/dev/null 2>&1; then
    log "rebuilding initramfs images $reason"
    mkinitcpio -P
  elif command -v update-initramfs >/dev/null 2>&1; then
    log "rebuilding initramfs images $reason"
    update-initramfs -u -k all
  elif command -v dracut >/dev/null 2>&1; then
    log "rebuilding initramfs images $reason"
    dracut --force --regenerate-all
  else
    warn "no initramfs generator found; initramfs was not rebuilt"
  fi
}

# ---------------------------------------------------------- kernel cmdline

GRUB_FILE="${GRUB_FILE:-/etc/default/grub}"
KERNELSTUB_FILE="${KERNELSTUB_FILE:-/etc/kernelstub/configuration}"
LIMINE_DROPIN_DIR="${LIMINE_DROPIN_DIR:-/etc/limine-entry-tool.d}"
LIMINE_CMDLINE_DROPIN="$LIMINE_DROPIN_DIR/95-asus-expertbook-linux-cmdline.conf"

# cmdline_backend -> limine | kernelstub | grub | none
#
# Limine is probed first so Arch/CachyOS keeps using the source of truth
# display-fix already writes to. CMDLINE_BACKEND forces a backend (testing, or
# a machine where the probe guesses wrong).
cmdline_backend() {
  if [[ -n ${CMDLINE_BACKEND:-} ]]; then
    printf '%s\n' "$CMDLINE_BACKEND"
  elif command -v limine-update >/dev/null 2>&1 ||
       command -v limine-mkinitcpio >/dev/null 2>&1; then
    echo limine
  elif command -v kernelstub >/dev/null 2>&1; then
    echo kernelstub
  elif [[ -f $GRUB_FILE ]] &&
       { command -v update-grub >/dev/null 2>&1 ||
         command -v grub-mkconfig >/dev/null 2>&1; }; then
    echo grub
  else
    echo none
  fi
}

# cmdline_active <param> -- is the exact token on the running kernel cmdline?
cmdline_active() {
  local want="$1" token
  while IFS= read -r token; do
    [[ $token == "$want" ]] && return 0
  done < <(tr ' ' '\n' < /proc/cmdline 2>/dev/null || true)
  return 1
}

# cmdline_active_value <key> -- value of key=... on the running cmdline.
cmdline_active_value() {
  local key="$1" token value=""
  while IFS= read -r token; do
    [[ $token == "$key="* ]] && value="${token#*=}"
  done < <(tr ' ' '\n' < /proc/cmdline 2>/dev/null || true)
  printf '%s\n' "$value"
}

_grub_options() {
  [[ -f $GRUB_FILE ]] || return 0
  sed -n 's/^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"[[:space:]]*$/\1/p' \
    "$GRUB_FILE" | tail -n1
}

# _grub_write_options <new-cmdline> -- replace GRUB_CMDLINE_LINUX_DEFAULT.
#
# The replacement is atomic. Truncating the live file and rewriting it in place
# would leave an empty or half-written /etc/default/grub if the write were cut
# short, which is not a risk worth taking on a bootloader config. Instead the
# new content is staged beside the target and renamed over it in one step.
#
# Two details the obvious version gets wrong:
#   - the staging file must live in the target's own directory. mktemp defaults
#     to /tmp, which is frequently a separate filesystem, and rename(2) across
#     filesystems is not atomic -- mv silently degrades to copy-then-unlink.
#   - rename installs a new inode, so mode and ownership have to be carried
#     over explicitly; the previous in-place write got them for free.
#
# GRUB_FILE may be a symlink (and is one in some /etc layouts), so resolve it
# first: the rename has to land on the real file rather than replace the link.
# Returns non-zero without touching the target when staging or writing fails.
_grub_write_options() {
  local new="$1" target dir tmp
  target="$(readlink -f -- "$GRUB_FILE" 2>/dev/null || printf '%s\n' "$GRUB_FILE")"
  dir="$(dirname -- "$target")"

  # _grub_options only understands a plain double-quoted value. Rewriting any
  # other form (single quotes, no quotes, a continuation) would drop the
  # arguments it could not read, so leave those to the user.
  if grep -qE '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$target" &&
     grep -E '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$target" |
       grep -qvE '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"[[:space:]]*$'; then
    warn "GRUB_CMDLINE_LINUX_DEFAULT in $target is not a plain double-quoted value; edit it by hand"
    return 1
  fi

  tmp="$(mktemp -- "$dir/.grub.XXXXXX")" || {
    warn "cannot stage a replacement for $target in $dir"
    return 1
  }
  chmod --reference="$target" -- "$tmp" 2>/dev/null || true
  chown --reference="$target" -- "$tmp" 2>/dev/null || true

  if ! awk -v repl="GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"" '
    /^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/ {
      if (!seen) { print repl; seen = 1 }
      next
    }
    { print }
    END { if (!seen) print repl }
  ' "$target" > "$tmp"; then
    rm -f -- "$tmp"
    warn "failed to build the replacement for $target"
    return 1
  fi

  mv -f -- "$tmp" "$target" || {
    rm -f -- "$tmp"
    warn "failed to install the new $target"
    return 1
  }

  _grub_regen
}

_grub_regen() {
  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

_limine_regen() {
  if command -v limine-update >/dev/null 2>&1; then
    limine-update
  elif command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
  else
    warn "Limine tooling not found; kernel parameters were not activated"
    return 1
  fi
}

# cmdline_configured <param> -- staged in the bootloader config (may still
# need a reboot to become active)?
cmdline_configured() {
  local param="$1" token
  case "$(cmdline_backend)" in
    limine)
      [[ -f $LIMINE_CMDLINE_DROPIN ]] &&
        grep -qF -- "$param" "$LIMINE_CMDLINE_DROPIN"
      ;;
    kernelstub)
      [[ -f $KERNELSTUB_FILE ]] &&
        grep -qF -- "\"$param\"" "$KERNELSTUB_FILE"
      ;;
    grub)
      for token in $(_grub_options); do
        [[ $token == "$param" ]] && return 0
      done
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# cmdline_add <param>... -- idempotent. Returns non-zero when the parameters
# were staged but the bootloader could not be regenerated. GRUB is regenerated
# on every call, so running it again retries a failed grub-mkconfig.
cmdline_add() {
  (( $# > 0 )) || return 0
  local param opts changed=0 rc=0
  case "$(cmdline_backend)" in
    limine)
      install -d -m 0755 "$LIMINE_DROPIN_DIR"
      for param in "$@"; do
        cmdline_configured "$param" && continue
        printf 'KERNEL_CMDLINE[default]+=" %s"\n' "$param" \
          >> "$LIMINE_CMDLINE_DROPIN"
        changed=1
      done
      if (( changed )); then
        _limine_regen || rc=1
      fi
      ;;
    kernelstub)
      # Callers test the result (`cmdline_add ... || die`), which turns off
      # errexit in here, so a failed kernelstub has to be counted by hand.
      for param in "$@"; do
        cmdline_configured "$param" && continue
        kernelstub -a "$param" >/dev/null || rc=1
        changed=1
      done
      ;;
    grub)
      opts=" $(_grub_options) "
      for param in "$@"; do
        [[ $opts == *" $param "* ]] && continue
        opts="$opts$param "
        changed=1
      done
      if (( changed )); then
        opts="${opts#"${opts%%[![:space:]]*}"}"
        opts="${opts%"${opts##*[![:space:]]}"}"
        _grub_write_options "$opts" || rc=1
      else
        # Already in /etc/default/grub, possibly from a run whose regeneration
        # failed: regenerate anyway so grub.cfg cannot stay behind.
        _grub_regen || rc=1
      fi
      ;;
    *)
      warn "no supported bootloader backend; add by hand to the kernel cmdline: $*"
      return 1
      ;;
  esac
  return "$rc"
}

# cmdline_remove <param>... -- idempotent. Returns non-zero when the change
# was staged but the bootloader could not be regenerated.
cmdline_remove() {
  (( $# > 0 )) || return 0
  local param opts token new changed=0 rc=0 tmp
  case "$(cmdline_backend)" in
    limine)
      [[ -f $LIMINE_CMDLINE_DROPIN ]] || return 0
      for param in "$@"; do
        cmdline_configured "$param" || continue
        tmp="$(mktemp)"
        grep -vF -- "$param" "$LIMINE_CMDLINE_DROPIN" > "$tmp" || true
        cat -- "$tmp" > "$LIMINE_CMDLINE_DROPIN"
        rm -f -- "$tmp"
        changed=1
      done
      [[ -s $LIMINE_CMDLINE_DROPIN ]] || rm -f -- "$LIMINE_CMDLINE_DROPIN"
      if (( changed )); then
        _limine_regen || rc=1
      fi
      ;;
    kernelstub)
      for param in "$@"; do
        cmdline_configured "$param" || continue
        kernelstub -d "$param" >/dev/null || rc=1
        changed=1
      done
      ;;
    grub)
      new=""
      for token in $(_grub_options); do
        for param in "$@"; do
          if [[ $token == "$param" ]]; then
            changed=1
            continue 2
          fi
        done
        new="$new$token "
      done
      if (( changed )); then
        new="${new%"${new##*[![:space:]]}"}"
        _grub_write_options "$new" || rc=1
      else
        _grub_regen || rc=1
      fi
      ;;
    *)
      warn "no supported bootloader backend; remove by hand from the kernel cmdline: $*"
      return 1
      ;;
  esac
  return "$rc"
}

# ------------------------------------------------------------------ services

# svc_unit <candidate>... -- first unit file that exists. Falls back to the
# first candidate so status output always has a name to print.
#
# Not paranoia: intel-lpmd ships as intel_lpmd.service on Arch, and the unit
# name is a packaging decision each distribution makes independently.
svc_unit() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "$(systemctl list-unit-files --no-legend "$candidate" 2>/dev/null)" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' "${1:-}"
}

svc_exists() {
  [[ -n "$(systemctl list-unit-files --no-legend "$1" 2>/dev/null)" ]]
}

svc_is_active() {
  systemctl is-active --quiet "$1"
}

svc_enable_now() {
  systemctl enable --now "$1"
}

svc_disable_now() {
  systemctl disable --now "$1"
}
