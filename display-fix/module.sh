# shellcheck shell=bash
# display-fix module manifest.
#
# Two xe overrides for the B9406CAA's Samsung OLED, both on the kernel cmdline.
# `xe.enable_dpcd_backlight=2` forces the VESA AUX/DPCD backlight interface,
# without which sysfs brightness changes but panel luminance doesn't.
# `xe.enable_panel_replay=0 xe.enable_psr=1` runs self-refresh as PSR1 instead
# of Linux 7.2's Panther Lake default, Panel Replay with Selective Update and
# Early Transport. In that default mode the panel comes up visibly desaturated
# after every HDR-enabling modeset and leaves stale content on screen; the
# colors return once anything streams frames with the SDPs again (a KWin
# color-accuracy toggle, a write to i915_edp_psr_debug), so the panel seems to
# miss the new BT.2020/PQ signaling when Panel Replay stops the stream on a
# static desktop. Dropping only Early Transport keeps the washed out colors and
# slows the cursor to ~20 fps, so Panel Replay itself is at fault.
#
# Disabling Panel Replay alone is worse: xe falls back to PSR2 selective update
# over the panel's DSC link and every screen update paints red/green speckle
# garbage, most likely because xe gates PSR2 + DSC on platform generation only
# while this sink advertises DSC selective update for Panel Replay alone.
# Disabling only selective fetch (`xe.enable_psr2_sel_fetch=0`) keeps Panel
# Replay without selective update, which freezes the panel on the boot console
# text. PSR1 passes everything: vivid colors across HDR toggles, a smooth
# cursor, no stale frames, and self-refresh still saves power on a static
# screen. Both PSR parameters are needed, since `enable_psr=1` alone leaves
# Panel Replay on (Panel Replay bypasses the PSR2 checks that parameter feeds
# into). The older `xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0` pair
# lands on PSR1 too: Panther Lake has no PSR2 hardware tracking to fall back on
# without selective fetch. `enable_psr=1` says it directly; status accepts both.
#
# modprobe.d alone is NOT enough: xe loads from the initramfs before
# /etc/modprobe.d is honoured, so the params have to land on the kernel
# cmdline. Which file that means depends on the bootloader, so the parameters
# go through lib/distro.sh's cmdline backend.
#
# On Limine that backend is bypassed: we keep installing the managed
# `limine-entry-tool` drop-in verbatim, because it is the CachyOS source of
# truth (`/etc/default/limine` is not used by current limine-mkinitcpio-hook
# releases) and because it carries its own explanatory comment into
# /etc/limine-entry-tool.d. cmdline_add's generic Limine branch would write a
# bare KERNEL_CMDLINE line to a different drop-in instead. Everywhere else
# (kernelstub on Pop!_OS, GRUB on Debian/Ubuntu) cmdline_add owns the change.
#
# We still drop the modprobe.d file as belt-and-suspenders for any future
# scenario where xe is rmmod'd and re-loaded post-boot. Install also removes
# the old `xe-disable-psr.conf`, which turned self-refresh off entirely.
#
# `asus-expertbook-b9406-display.conf` is Omarchy's own drop-in for this
# laptop. It sets only `xe.enable_panel_replay=0`, which agrees with PSR1, so
# it stays. It sorts after our 90- file and wins on the cmdline, so a
# hand-edited copy that sets another PSR or Panel Replay value is archived.
# Version 1.3 archived Omarchy's stock copy as well; install puts that back.

MODULE_NAME="display-fix"
MODULE_DESC="B9406CAA xe: PSR1 self-refresh + working DPCD brightness"
MODULE_VERSION="1.5.0"

DISPLAY_FIX_DROPIN="/etc/limine-entry-tool.d/90-asus-expertbook-linux-display.conf"

# The three parameters the drop-in above carries, for the backends that take
# them one token at a time. Keep in sync with limine-display.conf.
DISPLAY_FIX_PARAMS=(
  "xe.enable_dpcd_backlight=2"
  "xe.enable_panel_replay=0"
  "xe.enable_psr=1"
)

MODULE_FILES=(
  "xe-dpcd-backlight.conf:/etc/modprobe.d/xe-dpcd-backlight.conf"
)

# Installing the drop-in where nothing consumes it would leave a dead file that
# uninstall still has to chase, and would make `status` list a payload that
# does nothing. On Limine the array is exactly what it has always been.
if [[ $(cmdline_backend) == limine ]]; then
  MODULE_FILES+=("limine-display.conf:$DISPLAY_FIX_DROPIN")
fi

# True when a Limine drop-in, comments aside, sets xe.enable_psr or
# xe.enable_panel_replay to anything but the PSR1 pair this module installs.
_df_fights_psr1() {
  local token
  while IFS= read -r token; do
    case $token in
      xe.enable_psr=1 | xe.enable_panel_replay=0) ;;
      xe.enable_psr=* | xe.enable_panel_replay=*) return 0 ;;
    esac
  done < <(sed 's/#.*//' -- "$1" | grep -o 'xe\.enable_[a-z0-9_]*=[^"[:space:]]*')
  return 1
}

_df_remove_obsolete_files() {
  local old_modprobe="/etc/modprobe.d/xe-disable-psr.conf"
  local omarchy_limine="/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf"
  local archived="${omarchy_limine}.disabled-by-asus-expertbook-linux"
  local dest

  if [[ -f $old_modprobe ]]; then
    rm -- "$old_modprobe"
    log "[display-fix] removed obsolete PSR-disable file $old_modprobe"
  fi

  if [[ -f $omarchy_limine ]]; then
    if _df_fights_psr1 "$omarchy_limine"; then
      dest=$archived
      if [[ -e $dest ]]; then
        dest="$archived.$(date +%Y%m%d%H%M%S)"
      fi
      mv -- "$omarchy_limine" "$dest"
      log "[display-fix] archived $omarchy_limine as $dest: it overrides the PSR1 parameters"
    fi
  elif [[ -f $archived ]] && ! _df_fights_psr1 "$archived"; then
    mv -- "$archived" "$omarchy_limine"
    log "[display-fix] restored Omarchy's Panel Replay drop-in $omarchy_limine"
  fi
}

_df_remove_legacy_block() {
  local legacy="/etc/default/limine"
  local begin="# >>> asus-expertbook-linux display-fix >>>"
  local end="# <<< asus-expertbook-linux display-fix <<<"

  if [[ -f $legacy ]] && grep -qF "$begin" "$legacy" && \
     grep -qF "$end" "$legacy"; then
    sed -i "/^${begin}$/,/^${end}$/d" "$legacy"
    log "[display-fix] removed the obsolete managed block from $legacy"
  fi
}

_df_regen_limine() {
  if command -v limine-update >/dev/null 2>&1; then
    log "[display-fix] regenerating Limine entries"
    limine-update
  elif command -v limine-mkinitcpio >/dev/null 2>&1; then
    log "[display-fix] regenerating Limine initramfs entries"
    limine-mkinitcpio
  else
    die "[display-fix] Limine tooling not found; kernel parameters were not activated"
  fi
}

# _df_apply <add|remove> -- put the three parameters on, or take them off, the
# kernel cmdline. The Limine branch is the pre-existing code path, unchanged:
# the drop-in is already in place (or already gone) by the time this runs, so
# all that is left is regenerating the entries.
_df_apply() {
  local action="$1"
  if [[ $(cmdline_backend) == limine ]]; then
    _df_regen_limine
    return 0
  fi

  if [[ $action == add ]]; then
    cmdline_add "${DISPLAY_FIX_PARAMS[@]}" ||
      die "[display-fix] kernel parameters were staged but the bootloader could not be updated"
  else
    cmdline_remove "${DISPLAY_FIX_PARAMS[@]}" ||
      die "[display-fix] kernel parameters were removed but the bootloader could not be updated"
  fi
}

module_post_install() {
  _df_remove_legacy_block
  _df_remove_obsolete_files
  _df_apply add
  echo
  echo "Reboot to apply: xe will run the panel in PSR1 with the VESA DPCD backlight forced."
}

module_post_uninstall() {
  _df_remove_legacy_block
  _df_remove_obsolete_files
  _df_apply remove
  echo
  echo "Reboot to return to the kernel's Panel Replay default and automatic backlight interface selection."
}

# _df_staged <param> -- the parameter is configured for the next boot.
# On Limine that is the managed drop-in; elsewhere the bootloader's own config,
# which cmdline_configured knows how to read.
_df_staged() {
  if [[ $(cmdline_backend) == limine ]]; then
    grep -qs -- "$1" "$DISPLAY_FIX_DROPIN"
  else
    cmdline_configured "$1"
  fi
}

module_status_extra() {
  local token backlight="" panel_replay="" psr="" sel_fetch=""

  while IFS= read -r token; do
    case $token in
      xe.enable_dpcd_backlight=*) backlight="${token#*=}" ;;
      xe.enable_panel_replay=*)   panel_replay="${token#*=}" ;;
      xe.enable_psr=*)            psr="${token#*=}" ;;
      xe.enable_psr2_sel_fetch=*) sel_fetch="${token#*=}" ;;
    esac
  done < <(tr ' ' '\n' </proc/cmdline 2>/dev/null)

  if [[ $panel_replay == 0 ]]; then
    if [[ $psr == 0 ]]; then
      printf '  self-refresh:%s xe.enable_psr=0 active: self-refresh fully off (expected PSR1)%s\n' \
        "$c_warn" "$c_off"
    elif [[ $psr == 1 ]]; then
      printf '  self-refresh:%s PSR1 active (xe.enable_panel_replay=0 xe.enable_psr=1)%s\n' \
        "$c_ok" "$c_off"
    elif [[ $sel_fetch == 0 ]]; then
      printf '  self-refresh:%s PSR1 active (xe.enable_panel_replay=0 xe.enable_psr2_sel_fetch=0)%s\n' \
        "$c_ok" "$c_off"
    else
      printf '  self-refresh:%s xe.enable_panel_replay=0 without xe.enable_psr=1: PSR2 selective update paints garbage on this panel%s\n' \
        "$c_warn" "$c_off"
    fi
  elif [[ $sel_fetch == 0 ]]; then
    printf '  self-refresh:%s xe.enable_psr2_sel_fetch=0 without xe.enable_panel_replay=0: Panel Replay without selective update freezes the panel at boot%s\n' \
      "$c_warn" "$c_off"
  elif _df_staged "xe.enable_panel_replay=0" && _df_staged "xe.enable_psr=1"; then
    printf '  self-refresh:%s PSR1 staged, reboot to apply (this boot runs the Panel Replay default)%s\n' \
      "$c_warn" "$c_off"
  else
    printf '  self-refresh:%s PSR1 not active; the kernel default (Panel Replay) is running%s\n' \
      "$c_warn" "$c_off"
  fi

  if [[ $backlight == 2 ]]; then
    printf '  backlight:%s xe.enable_dpcd_backlight=2 active (forced VESA interface)%s\n' \
      "$c_ok" "$c_off"
  elif [[ -n $backlight ]]; then
    printf '  backlight:%s effective xe.enable_dpcd_backlight=%s (expected 2)%s\n' \
      "$c_warn" "$backlight" "$c_off"
  elif _df_staged "xe.enable_dpcd_backlight=2"; then
    printf '  backlight:%s DPCD fix staged, reboot to apply%s\n' "$c_warn" "$c_off"
  else
    printf '  backlight:%s xe.enable_dpcd_backlight=2 is not active%s\n' "$c_warn" "$c_off"
  fi

  # debugfs is root-only, so this line shows under `sudo ./patch.sh status` and
  # the interactive menu (which re-executes under sudo) and stays silent for an
  # unprivileged caller. xe registers its device under
  # dri/0000:00:02.0 where i915 used dri/0, hence the glob; the per-connector
  # file is the authoritative one and the device-level file its older alias.
  local status_file="" candidate mode
  for candidate in /sys/kernel/debug/dri/*/eDP-*/i915_psr_status \
                   /sys/kernel/debug/dri/*/i915_edp_psr_status; do
    if [[ -r $candidate ]]; then
      status_file=$candidate
      break
    fi
  done
  [[ -n $status_file ]] || return 0

  mode="$(awk -F': ' '/^PSR mode:/ {print $2; exit}' "$status_file" 2>/dev/null)"
  [[ -n $mode ]] || return 0
  case $mode in
    "PSR1 enabled"*)
      printf '  panel:   %sPSR mode: %s%s\n' "$c_ok" "$mode" "$c_off" ;;
    *)
      printf '  panel:   %sPSR mode: %s (expected PSR1 enabled)%s\n' "$c_warn" "$mode" "$c_off" ;;
  esac
}
