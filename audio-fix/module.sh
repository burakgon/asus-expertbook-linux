# shellcheck shell=bash
# audio-fix module manifest. Sourced by ../patch.sh.
#
# Restores full speaker + headphone audio on the ASUS ExpertBook Ultra B9406CAA
# (PCI subsystem 1043:15e4) through the proper ALSA UCM "HiFi" profile.
#
#   1) cs35l56 amps need OEM tuning firmware (.bin tuning + .wmfw patch,
#      ROM 3.4.4 -> 3.13.4). linux-firmware-cirrus >= 20260519 ships these
#      upstream for 1043:15e4 (per-amp -l2uN.bin plus the generic Rev 3.13.4
#      .wmfw), byte-identical to the bundled copies. The bundled blobs are a
#      fallback for older linux-firmware only. Installed next to a current
#      package they would shadow it, and their per-amp -l2uN.wmfw names are
#      looked up before the package's generic .wmfw, so a newer Cirrus
#      firmware would never load. On current linux-firmware, install removes
#      copies that are identical to ours.
#
#   2) The card reports a combined speaker-codec component string
#      ("spk:cs35l56+cs42l43-spk", or two "spk:" tags on older kernels). Stock
#      alsa-ucm-conf 1.2.15.x has no UCM for it AND its SpeakerCodec regex drops
#      the trailing "-spk", so the UCM fails to open and PipeWire falls back to
#      an unrouted "stereo-fallback" profile that plays to the Jack PCM, not the
#      speakers. The upstream alsa-ucm-conf master files (Syntax 7) fix this:
#      sof-soundwire.conf (fixed regex) + the cs35l56+cs42l43-spk /
#      cs42l43-spk+cs35l56 speaker confs + the combined codec init. The UCM then
#      brings up a real HiFi profile: Speaker (hw:,2), Headphones (auto-switch on
#      jack), Headset/Internal Mic, HDMI 1-3, with working volume + mic-mute LED.
#
#      >> As of alsa-ucm-conf 1.2.16 these files ship UPSTREAM, verbatim. So on
#      1.2.16+ this module installs NOTHING under /usr/share/alsa/ucm2 and adds
#      no NoExtract pin -- doing either would only create pacman file-conflicts
#      on the next alsa-ucm-conf upgrade (the files already belong to the
#      package). The bundled UCM copies are kept solely as a fallback for systems
#      still on alsa-ucm-conf < 1.2.16 (see module_post_install). On 1.2.16+ the
#      module is effectively firmware + SSP2-BT-noise-fix only.
#
#   3) B9406CAA firmware advertises a ghost RT722 SoundWire codec on link 3.
#      New kernels keep it as UNATTACHED, but the generic sof_sdw machine driver
#      still creates its SimpleJack DAI alongside the real CS42L43. The duplicate
#      link aborts ALSA card registration. A board-scoped DKMS overlay filters
#      only that unattached RT722 on released kernels that need it. Upstream
#      commit 90af3209742d adds the permanent DMI quirk; install detects that
#      marker per kernel and skips/removes the redundant overlay automatically.
#      The same overlay works around Linux 7.2.11's half-backported OT25
#      series, which leaves no card at all. Kernels before 6.19 have no
#      machine driver match for this laptop, so they are skipped with a note.
#
#   4) The generic SOF topology declares an unused SSP2-BT hardware-offload PCM
#      with no firmware blob; WirePlumber's probe of it spams the kernel log
#      (~40% of all kernel errors at boot). 52-disable-bt-sco-offload.conf
#      disables that node. Bluetooth audio (A2DP music + HFP calls) keeps
#      working over the normal PipeWire software path. The Linux 7.1+ function
#      topologies no longer expose that PCM, so the drop-in is inert there; it
#      stays for older kernels.
#
#   5) SOF firmware and topologies come from the separate sof-firmware package
#      on Arch. A minimal install can lack it, and then no card appears even
#      with the ghost-RT722 fix ("SOF firmware and/or topology file not
#      found"). Install pulls it in; status reports it.
#
# This replaced the old "pro-audio profile pin" workaround (<= v1.3.0). HiFi is
# the correct approach: headphone jack auto-switching, named ports, working
# volume + mic-mute LED. NOTE: the speaker (F1) mute LED needs asus-wmi's
# platform::mute (WMI device 0x0004001C), which lands in Linux 7.4. Until then
# only platform::micmute exists; the kernel's audio-micmute trigger drives it.

MODULE_NAME="audio-fix"
MODULE_DESC="B9406CAA audio: adaptive ghost-RT722 fix + HiFi UCM + cs35l56 firmware"
MODULE_VERSION="3.4.0"

AUDIO_DKMS_NAME="asus-expertbook-sof-sdw"
AUDIO_DKMS_VERSION="3.0.3"
AUDIO_DKMS_SOURCE="$MODULE_DIR/dkms/${AUDIO_DKMS_NAME}-${AUDIO_DKMS_VERSION}"
AUDIO_DKMS_SRCDIR="/usr/src"
AUDIO_DKMS_TARGET="$AUDIO_DKMS_SRCDIR/${AUDIO_DKMS_NAME}-${AUDIO_DKMS_VERSION}"

# pacman hook that warns when a kernel update leaves the overlay unbuilt (#25).
AUDIO_CHECK="/usr/local/lib/asus-expertbook-audio-check"
AUDIO_CHECK_HOOK="/etc/pacman.d/hooks/90-asus-expertbook-audio-check.hook"

# Always-installed payload: the SSP2-BT topology-noise silencer. The OEM
# firmware and the HiFi UCM files are handled conditionally in
# module_post_install (upstream since linux-firmware-cirrus 20260519 and
# alsa-ucm-conf 1.2.16), so they are deliberately NOT listed here.
MODULE_FILES=(
  "52-disable-bt-sco-offload.conf:/etc/wireplumber/wireplumber.conf.d/52-disable-bt-sco-offload.conf"
)

# OEM speaker firmware -- installed only when linux-firmware lacks it.
FIRMWARE_FILES=(
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw"
)

# HiFi UCM payload -- needed only on alsa-ucm-conf < 1.2.16. 1.2.16+ ships these
# identical files in the package itself, so installing our copies would leave
# pacman-unowned files that collide on the next alsa-ucm-conf upgrade.
UCM_FILES=(
  "sof-soundwire.conf:/usr/share/alsa/ucm2/sof-soundwire/sof-soundwire.conf"
  "cs35l56+cs42l43-spk.conf:/usr/share/alsa/ucm2/sof-soundwire/cs35l56+cs42l43-spk.conf"
  "cs42l43-spk+cs35l56.conf:/usr/share/alsa/ucm2/sof-soundwire/cs42l43-spk+cs35l56.conf"
  "cs42l43-spk+cs35l56-init.conf:/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf"
)

# cirrus_firmware_is_upstream: true when linux-firmware already ships the
# 1043:15e4 CS35L56 tuning: on pacman systems linux-firmware-cirrus (or the
# pre-split linux-firmware) >= 20260519, and everywhere the files themselves,
# present and intact. A new package with missing files is reported for repair.
cirrus_firmware_is_upstream() {
  local v pkg have=""
  if command -v pacman >/dev/null 2>&1; then
    for pkg in linux-firmware-cirrus linux-firmware; do
      v="$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')" || true
      [[ -n $v ]] || continue
      v="${v#*:}"
      v="${v:0:8}"
      [[ $v =~ ^[0-9]{8}$ ]] || continue
      if (( v >= 20260519 )); then
        have="$pkg $v"
        break
      fi
    done
    [[ -n $have ]] || return 1
  fi
  cirrus_upstream_files_present && return 0
  if [[ -n $have ]]; then
    warn "[audio-fix] $have should ship the 1043:15e4 CS35L56 files, but they are missing or damaged;"
    warn "[audio-fix] using the bundled copies. Repair with: pacman -S ${have%% *}"
  fi
  return 1
}

# The package's replacements for the bundled files: per-amp tuning and the
# generic .wmfw. A compressed file counts only if it decompresses; an
# uncompressed one only when a package owns it, so our own leftovers never
# vouch for themselves.
cirrus_upstream_files_present() {
  local base f found
  for base in cs35l56-b0-dsp1-misc-104315e4-l2u0.bin cs35l56-b0-dsp1-misc-104315e4-l2u1.bin \
              cs35l56-b0-dsp1-misc-104315e4.wmfw; do
    f="/lib/firmware/cirrus/$base"
    found=0
    if [[ -e $f.zst ]]; then
      zstd -tq -- "$(readlink -f -- "$f.zst")" >/dev/null 2>&1 && found=1
    elif [[ -e $f.xz ]]; then
      xz -tq -- "$(readlink -f -- "$f.xz")" >/dev/null 2>&1 && found=1
    elif [[ -e $f ]] && command -v pacman >/dev/null 2>&1 && pacman -Qqo "$f" >/dev/null 2>&1; then
      found=1
    fi
    (( found )) || return 1
  done
  return 0
}

audio_install_firmware() {
  local entry src dst
  for entry in "${FIRMWARE_FILES[@]}"; do
    src="${entry%%:*}"; dst="${entry#*:}"
    if [[ -e $dst ]] && command -v pacman >/dev/null 2>&1 && pacman -Qqo "$dst" >/dev/null 2>&1; then
      warn "[audio-fix] leaving $dst: it belongs to a package"
      continue
    fi
    log "[audio-fix] installing -> $dst"
    install -D -m 0644 "$src" "$dst" || die "[audio-fix] cannot install $dst"
  done
}

# Remove only copies that are byte-identical to the bundled files, so a
# firmware the user placed deliberately is never deleted.
audio_remove_bundled_firmware() {
  local entry src dst removed=1
  for entry in "${FIRMWARE_FILES[@]}"; do
    src="${entry%%:*}"; dst="${entry#*:}"
    [[ -f $dst ]] || continue
    if command -v pacman >/dev/null 2>&1 && pacman -Qqo "$dst" >/dev/null 2>&1; then
      warn "[audio-fix] leaving $dst: it belongs to a package"
    elif cmp -s "$src" "$dst"; then
      rm -f -- "$dst"
      log "[audio-fix] removed bundled copy $dst"
      removed=0
    else
      warn "[audio-fix] leaving $dst: it differs from the bundled file"
    fi
  done
  return "$removed"
}

# Remove only our token from NoExtract lines, keeping every other entry and
# any trailing comment. The original is kept as pacman.conf.asus-expertbook-linux.bak.
audio_drop_noextract_pin() {
  local tok="usr/share/alsa/ucm2/sof-soundwire/sof-soundwire.conf" conf=/etc/pacman.conf tmp
  awk -v tok="$tok" '/^[[:space:]]*NoExtract[[:space:]]*=/ && index($0, tok) { f = 1 }
    END { exit !f }' "$conf" 2>/dev/null || return 0
  cp -a -- "$conf" "$conf.asus-expertbook-linux.bak" || return 1
  tmp="$(mktemp "${conf%/*}/.pacman.conf.XXXXXX")" || return 1
  if ! awk -v tok="$tok" '
      /^[[:space:]]*NoExtract[[:space:]]*=/ {
        rest = $0; comment = ""
        sub(/^[[:space:]]*NoExtract[[:space:]]*=[[:space:]]*/, "", rest)
        if (match(rest, /#/)) { comment = substr(rest, RSTART); rest = substr(rest, 1, RSTART - 1) }
        n = split(rest, word, /[[:space:]]+/)
        out = ""; hit = 0
        for (i = 1; i <= n; i++) {
          if (word[i] == tok) { hit = 1; continue }
          if (word[i] != "") out = out (out == "" ? "" : " ") word[i]
        }
        if (hit) {
          if (out != "") print "NoExtract = " out (comment != "" ? " " comment : "")
          else if (comment != "") print comment
          next
        }
      }
      { print }' "$conf" >"$tmp" ||
     ! chmod --reference="$conf" "$tmp" || ! mv -f -- "$tmp" "$conf"; then
    rm -f -- "$tmp"
    warn "[audio-fix] could not edit $conf; remove $tok from its NoExtract line by hand"
    return 1
  fi
  log "[audio-fix] removed the sof-soundwire.conf NoExtract pin from $conf (backup: $conf.asus-expertbook-linux.bak)"
}

# SOF DSP firmware and topologies are a separate Arch package (#23).
audio_require_sof_firmware() {
  command -v pacman >/dev/null 2>&1 || return 0
  pacman -Q sof-firmware >/dev/null 2>&1 && return 0
  log "[audio-fix] installing sof-firmware (SOF DSP firmware and topologies)"
  pacman -S --needed --noconfirm sof-firmware
}

# ucm_hifi_is_upstream: true when the installed alsa-ucm-conf already ships the
# combined cs35l56+cs42l43-spk HiFi UCM (>= 1.2.16). Falls back to false when
# the version cannot be determined, and we install the bundled copies.
ucm_hifi_is_upstream() {
  pkg_atleast alsa-ucm-conf 1.2.16
}

# The per-kernel rules (audio_kernel_has_upstream_ghost_quirk,
# audio_kernel_fixed_upstream, audio_kernel_predates_card) live in the pacman
# check, so install and the post-update warning use the same ones.
# shellcheck source=asus-expertbook-audio-check
source "$MODULE_DIR/asus-expertbook-audio-check"

audio_dkms_installed_for_kernel() {
  local kernel="${1:-$(uname -r)}" status=""
  command -v dkms >/dev/null 2>&1 || return 1
  status="$(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" \
    -k "$kernel" 2>/dev/null || true)"
  [[ $status == *installed* ]]
}

# Make `list`/`update-all` offer reconciliation after a distro kernel gains the
# upstream DMI quirk, and catch a missing overlay on older kernels.
module_install_state() {
  local files installed
  files="$(mod_files_state)"
  installed="$(mod_get_installed_version)"
  case "$files" in
    none) echo not-installed; return ;;
    some) echo partial; return ;;
  esac

  if audio_kernel_fixed_upstream; then
    if audio_dkms_installed_for_kernel; then
      echo update-available
      return
    fi
  elif ! audio_kernel_predates_card && ! audio_dkms_installed_for_kernel; then
    echo partial
    return
  fi

  if [[ -z $installed ]]; then
    echo untracked
  elif [[ $installed == "$MODULE_VERSION" ]]; then
    echo up-to-date
  else
    echo update-available
  fi
}

# DKMS modules this repository installed before, oldest first. Exact names,
# never a wildcard: the two experimental modules it superseded, overlay 3.0.0
# (cannot build on Linux 7.2.8+), 3.0.1 (no kernel range, so DKMS also built
# it for 7.3+, whose own sof_sdw is newer and has the quirk) and 3.0.2 (no
# card on 7.2.11, and DKMS still tried the 6.18 LTS).
AUDIO_DKMS_LEGACY=(
  "sof-sdw-simplejack-fix/0.1"
  "soundwire-intel-b9406-ghostfix/0.1"
  "asus-expertbook-sof-sdw/3.0.0"
  "asus-expertbook-sof-sdw/3.0.1"
  "asus-expertbook-sof-sdw/3.0.2"
)

# State of DKMS module $1 (name/version) on kernel $2: "installed", "built"
# or nothing.
audio_dkms_state_of() {
  local out
  out="$(dkms status -m "${1%/*}" -v "${1#*/}" -k "$2" 2>/dev/null || true)"
  case $out in
    *", $2, "*": installed"*) echo installed ;;
    *", $2, "*": built"*)     echo built ;;
  esac
}

audio_dkms_state() {
  audio_dkms_state_of "$AUDIO_DKMS_NAME/$AUDIO_DKMS_VERSION" "$1"
}

AUDIO_RETIRED=()

# Unregister every superseded overlay and delete its source. A DKMS failure
# stops here and keeps the source, so the registration stays repairable.
# Succeeds when something was removed.
audio_remove_legacy_dkms() {
  local legacy name version source removed=1
  for legacy in "${AUDIO_DKMS_LEGACY[@]}"; do
    name="${legacy%/*}"
    version="${legacy#*/}"
    source="$AUDIO_DKMS_SRCDIR/${name}-${version}"

    if command -v dkms >/dev/null 2>&1 &&
       [[ -n $(dkms status -m "$name" -v "$version" 2>/dev/null || true) ]]; then
      log "[audio-fix] removing superseded DKMS module $legacy"
      dkms remove -m "$name" -v "$version" --all ||
        die "[audio-fix] DKMS could not remove $legacy; its source in $source is kept"
      removed=0
    fi
    if [[ -e $source ]]; then
      rm -rf -- "$source" || die "[audio-fix] could not remove $source"
      removed=0
    fi
  done
  return "$removed"
}

# Take every superseded overlay off kernel $1 with `dkms uninstall`, which
# puts the stock module back but keeps the build, so a failed swap can
# reinstall it without compiling. What was taken off goes in AUDIO_RETIRED.
audio_retire_legacy_on() {
  local legacy
  AUDIO_RETIRED=()
  for legacy in "${AUDIO_DKMS_LEGACY[@]}"; do
    [[ $(audio_dkms_state_of "$legacy" "$1") == installed ]] || continue
    log "[audio-fix] taking $legacy off $1"
    dkms uninstall -m "${legacy%/*}" -v "${legacy#*/}" -k "$1" ||
      die "[audio-fix] DKMS could not uninstall $legacy from $1"
    AUDIO_RETIRED+=("$legacy")
  done
}

# Reinstall what audio_retire_legacy_on took off kernel $1, from its kept
# build. Fails when any of it could not be put back.
audio_restore_legacy_on() {
  local legacy rc=0
  for legacy in "${AUDIO_RETIRED[@]}"; do
    if dkms install -m "${legacy%/*}" -v "${legacy#*/}" -k "$1"; then
      log "[audio-fix] put $legacy back on $1"
    else
      warn "[audio-fix] could not put $legacy back on $1"
      rc=1
    fi
  done
  return "$rc"
}

# Superseded overlay sources were copied with the checkout owner's ownership
# by older versions; root compiles them, so take them over before any DKMS
# call can use them.
audio_secure_legacy_sources() {
  local legacy source
  for legacy in "${AUDIO_DKMS_LEGACY[@]}"; do
    source="$AUDIO_DKMS_SRCDIR/${legacy%/*}-${legacy#*/}"
    [[ -d $source ]] || continue
    if ! chown -R root:root -- "$source" || ! chmod -R go-w -- "$source"; then
      die "[audio-fix] cannot give $source to root"
    fi
  done
}

audio_require_build_tools() {
  local missing=() tool
  for tool in dkms make clang; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done

  if (( ${#missing[@]} > 0 )); then
    log "[audio-fix] installing required build tools: ${missing[*]}"
    pkg_install "${missing[@]}" || die "[audio-fix] missing build tools: ${missing[*]}"
  fi

  # Headers for the running kernel only when it gets the overlay; every other
  # kernel's headers are checked where it is built.
  if audio_kernel_fixed_upstream || audio_kernel_predates_card; then
    return 0
  fi
  kernel_headers_present || \
    kernel_headers_install || \
    die "[audio-fix] kernel headers missing for $(uname -r)"
}

audio_install_dkms() {
  local kernel legacy needed=0 changed=0 keep=0 rc
  local -a build_kernels=() uncovered=() built=() failed=() held=() unresolved=()

  [[ -f $AUDIO_DKMS_SOURCE/dkms.conf ]] || \
    die "[audio-fix] bundled DKMS source is missing: $AUDIO_DKMS_SOURCE"

  # Preserve the previous convenience for the common case: when the running
  # kernel still needs DKMS, install its matching headers before inventorying
  # buildable kernels.
  # Before anything can install packages: a new headers package runs the DKMS
  # pacman hook, which reads every source under /usr/src as root.
  audio_secure_legacy_sources
  if ! audio_kernel_fixed_upstream && ! audio_kernel_predates_card; then
    audio_require_build_tools
  fi

  # Re-running install with the same, unchanged overlay keeps every working
  # build and only builds kernels that lack one. The same version with other
  # source would have to replace working builds in place, so overlay changes
  # get a new version instead.
  if command -v dkms >/dev/null 2>&1 && \
     [[ -n $(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" \
       2>/dev/null || true) ]]; then
    diff -rq "$AUDIO_DKMS_SOURCE" "$AUDIO_DKMS_TARGET" >/dev/null 2>&1 ||
      die "[audio-fix] the registered $AUDIO_DKMS_NAME $AUDIO_DKMS_VERSION differs from this checkout; to rebuild it anyway: dkms remove -m $AUDIO_DKMS_NAME -v $AUDIO_DKMS_VERSION --all"
    keep=1
    # Older installs copied the checkout owner along; root compiles this.
    if ! chown -R root:root -- "$AUDIO_DKMS_TARGET" || ! chmod -R go-w -- "$AUDIO_DKMS_TARGET"; then
      die "[audio-fix] cannot give $AUDIO_DKMS_TARGET to root"
    fi
  fi
  (( keep )) || rm -rf -- "$AUDIO_DKMS_TARGET"

  while IFS= read -r kernel; do
    # Not a failure to report: no overlay can give that kernel a card.
    if audio_kernel_predates_card "$kernel"; then
      warn "[audio-fix] skipping $kernel: before Linux 6.19 no machine driver matches this laptop's codecs, so it has no speakers with or without the overlay"
      continue
    fi
    if audio_kernel_fixed_upstream "$kernel"; then
      log "[audio-fix] $kernel contains upstream B9406CAA ghost-RT722 quirk; DKMS not needed"
      # Retire a build an earlier run or DKMS autoinstall left for it.
      if (( keep )) && [[ -n $(audio_dkms_state "$kernel") ]]; then
        dkms remove -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" -k "$kernel" </dev/null ||
          die "[audio-fix] could not remove the overlay from $kernel"
        log "[audio-fix] removed the overlay from $kernel"
        changed=1
      fi
      continue
    fi

    needed=$(( needed + 1 ))
    if ! kernel_headers_present "$kernel"; then
      warn "[audio-fix] skipping $kernel: upstream quirk absent and matching headers are not installed"
      uncovered+=("$kernel")
      continue
    fi
    build_kernels+=("$kernel")
  done < <(kernel_list)

  # Removing the last build of a version unregisters it.
  if (( keep )) && [[ -z $(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" 2>/dev/null || true) ]]; then
    keep=0
  fi

  if (( needed == 0 )); then
    if [[ -n $(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" 2>/dev/null || true) ]]; then
      dkms remove -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" --all ||
        die "[audio-fix] could not remove the redundant DKMS overlay"
      changed=1
    fi
    rm -rf -- "$AUDIO_DKMS_TARGET"
    if audio_remove_legacy_dkms; then
      changed=1
    fi
    log "[audio-fix] no installed kernel needs the DKMS overlay (the upstream DMI quirk, or Linux before 6.19)"
    if (( changed )); then
      audio_refresh_initramfs "with the stock upstream SoundWire quirk"
    fi
    return 0
  fi

  (( ${#build_kernels[@]} > 0 )) || \
    die "[audio-fix] kernels need the ghost-RT722 overlay, but no matching headers were found"

  audio_require_build_tools
  if (( ! keep )); then
    # Root compiles this source into a kernel module, so it must not keep the
    # checkout owner's ownership (cp -a would): root:root, not user-writable.
    if ! install -d -m 0755 "$AUDIO_DKMS_TARGET" ||
       ! cp -R -- "$AUDIO_DKMS_SOURCE/." "$AUDIO_DKMS_TARGET/" ||
       ! chown -R root:root -- "$AUDIO_DKMS_TARGET" ||
       ! chmod -R go-w -- "$AUDIO_DKMS_TARGET" ||
       ! dkms add -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION"; then
      die "[audio-fix] could not register the $AUDIO_DKMS_VERSION overlay with DKMS"
    fi
  fi

  # Compile first: nothing installed changes while builds can still fail.
  for kernel in "${build_kernels[@]}"; do
    case $(audio_dkms_state "$kernel") in
      installed)
        log "[audio-fix] DKMS overlay $AUDIO_DKMS_VERSION already installed for $kernel"
        continue ;;
      built)
        built+=("$kernel")
        continue ;;
    esac
    log "[audio-fix] building DKMS overlay $AUDIO_DKMS_VERSION for $kernel"
    if dkms build -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" -k "$kernel"; then
      built+=("$kernel")
    else
      rc=$?
      if (( rc == 77 )); then
        warn "[audio-fix] $kernel lacks the upstream quirk but is newer than the overlay's 7.2 code; no overlay for it"
        uncovered+=("$kernel")
      else
        warn "[audio-fix] the DKMS overlay failed to build for $kernel"
        failed+=("$kernel")
      fi
    fi
  done

  # Swap kernel by kernel: take the older overlays off a kernel only once its
  # new build exists, and put them back if installing that build fails.
  # Kernels without a new build keep whatever they run now.
  for kernel in "${built[@]}"; do
    audio_retire_legacy_on "$kernel"
    (( ${#AUDIO_RETIRED[@]} == 0 )) || changed=1
    log "[audio-fix] installing DKMS overlay $AUDIO_DKMS_VERSION for $kernel"
    if dkms install -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" -k "$kernel"; then
      changed=1
    else
      warn "[audio-fix] the DKMS overlay failed to install for $kernel"
      failed+=("$kernel")
      if ! audio_restore_legacy_on "$kernel"; then
        unresolved+=("$kernel")
      fi
    fi
  done

  # Kernels that got no new overlay: still running an older one (held), or
  # running none at all (unresolved, e.g. after a rollback failed earlier).
  local running
  for kernel in "${failed[@]}" "${uncovered[@]}"; do
    running=""
    for legacy in "${AUDIO_DKMS_LEGACY[@]}"; do
      if [[ $(audio_dkms_state_of "$legacy" "$kernel") == installed ]]; then
        running=$legacy
        break
      fi
    done
    if [[ -n $running ]]; then
      held+=("$kernel ($running)")
    elif [[ " ${unresolved[*]} " != *" $kernel "* ]]; then
      unresolved+=("$kernel")
    fi
  done

  # Superseded overlays (and their sources and builds) go only when every
  # kernel that needs the overlay has the new one: a failed or uncovered kernel
  # may still need them, even if it no longer runs them (a rollback that failed
  # on an earlier run leaves the older build uninstalled but kept).
  if (( ${#failed[@]} == 0 && ${#uncovered[@]} == 0 && ${#unresolved[@]} == 0 )) &&
     audio_remove_legacy_dkms; then
    changed=1
  fi

  if (( changed )); then
    audio_refresh_initramfs "with the DKMS overlay"
  fi
  if (( ${#held[@]} > 0 )); then
    warn "[audio-fix] kept the older overlay for: ${held[*]}"
  fi
  (( ${#unresolved[@]} == 0 )) || \
    die "[audio-fix] no overlay at all on: ${unresolved[*]}; the older builds and sources are kept, see 'dkms status'"
  (( ${#failed[@]} == 0 )) || \
    die "[audio-fix] no new ghost-RT722 overlay for: ${failed[*]} (see 'dkms status' and the make.log under /var/lib/dkms/$AUDIO_DKMS_NAME)"
  (( ${#uncovered[@]} == 0 )) || \
    die "[audio-fix] no overlay for: ${uncovered[*]} (no headers, or newer than the overlay's 7.2 code); the speakers will not work when booting it"
  return 0
}

AUDIO_INITRAMFS_REFRESHED=0

audio_refresh_initramfs() {
  local reason="${1:-after the audio driver change}"
  AUDIO_INITRAMFS_REFRESHED=1
  # sof_sdw may be included in an autodetected initramfs. Rebuild it now so the
  # selected stock/DKMS copy is consistent at the next boot.
  initramfs_regen "$reason"
}

audio_remove_dkms() {
  if command -v dkms >/dev/null 2>&1 && \
     [[ -n $(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" \
       2>/dev/null || true) ]]; then
    dkms remove -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" --all
  fi
  rm -rf -- "$AUDIO_DKMS_TARGET"
  audio_remove_legacy_dkms || true

  audio_refresh_initramfs "after removing the DKMS overlay"
}

# The check has nothing to say where no kernel can need the overlay, but it
# stays installed: the next kernel update may bring one that does.
audio_install_check() {
  [[ $(pkg_manager) == pacman ]] || return 0
  install -D -m 0755 "$MODULE_DIR/asus-expertbook-audio-check" "$AUDIO_CHECK" ||
    die "[audio-fix] cannot install $AUDIO_CHECK"
  install -d -m 0755 "${AUDIO_CHECK_HOOK%/*}" ||
    die "[audio-fix] cannot create ${AUDIO_CHECK_HOOK%/*}"
  sed "s|@AUDIO_DKMS@|$AUDIO_DKMS_NAME/$AUDIO_DKMS_VERSION|" \
    "$MODULE_DIR/asus-expertbook-audio-check.hook" >"$AUDIO_CHECK_HOOK" &&
    chmod 0644 "$AUDIO_CHECK_HOOK" ||
    die "[audio-fix] cannot install $AUDIO_CHECK_HOOK"
  log "[audio-fix] installed the post-update overlay check -> $AUDIO_CHECK_HOOK"
}

audio_remove_check() {
  rm -f -- "$AUDIO_CHECK_HOOK" "$AUDIO_CHECK"
}

module_post_install() {
  local fw_changed=0
  audio_require_sof_firmware

  # Firmware first: an initramfs rebuilt afterwards must not keep stale copies.
  if cirrus_firmware_is_upstream; then
    log "[audio-fix] linux-firmware ships the 1043:15e4 CS35L56 tuning -- not installing bundled firmware."
    audio_remove_bundled_firmware && fw_changed=1
  else
    audio_install_firmware
    fw_changed=1
  fi

  audio_install_dkms
  audio_install_check
  if (( fw_changed && ! AUDIO_INITRAMFS_REFRESHED )); then
    audio_refresh_initramfs "after the speaker firmware change"
  fi

  if ucm_hifi_is_upstream; then
    local v; v="$(pkg_version alsa-ucm-conf)"
    log "[audio-fix] alsa-ucm-conf ${v} ships the cs35l56+cs42l43-spk HiFi UCM upstream -- not installing bundled UCM (firmware-only)."
    # If an older version of this module pinned sof-soundwire.conf via NoExtract,
    # drop the pin so the packaged file tracks future upgrades normally.
    audio_drop_noextract_pin
  else
    # alsa-ucm-conf < 1.2.16 (or non-Arch): install the upstream-master UCM files
    # so the combined speaker codec resolves to a real HiFi profile.
    local entry src dst
    for entry in "${UCM_FILES[@]}"; do
      src="${entry%%:*}"; dst="${entry#*:}"
      log "[audio-fix] installing -> $dst"
      install -D -m 0644 "$src" "$dst"
    done
    # Recent kernels request the codec init under "cs35l56+cs42l43-spk"; older
    # ones (two spk: tags) under "cs42l43-spk+cs35l56". Symlink so both resolve.
    ln -sfn cs42l43-spk+cs35l56 /usr/share/alsa/ucm2/codecs/cs35l56+cs42l43-spk
    # Pin our sof-soundwire.conf so an alsa-ucm-conf upgrade doesn't revert the
    # SpeakerCodec regex fix. (Re-running this module after the upgrade crosses
    # 1.2.16 drops the pin automatically.)
    # NoExtract is a pacman feature; the Debian analogue is dpkg-divert and is
    # deliberately not wired up yet.
    if [[ $(pkg_manager) == pacman ]] && \
       ! grep -q "ucm2/sof-soundwire/sof-soundwire.conf" /etc/pacman.conf; then
      sed -i '/^#NoExtract/a NoExtract   = usr/share/alsa/ucm2/sof-soundwire/sof-soundwire.conf' /etc/pacman.conf
    fi
  fi

  echo "Run 'systemctl --user restart wireplumber' (or reboot) so the HiFi UCM"
  echo "loads. Default sink becomes '...sof_sdw.HiFi__Speaker__sink'."
}

module_post_uninstall() {
  # Firmware first, so the initramfs rebuilt by audio_remove_dkms holds no copy.
  audio_remove_bundled_firmware || true
  audio_remove_check
  audio_remove_dkms

  # Only tear down UCM files we placed ourselves. When alsa-ucm-conf >= 1.2.16
  # owns them, leave them be -- removing package files would break audio and
  # re-trigger the file-conflict on the next upgrade.
  if ! ucm_hifi_is_upstream; then
    local entry dst
    for entry in "${UCM_FILES[@]}"; do
      dst="${entry#*:}"
      rm -f -- "$dst"
    done
    rm -f /usr/share/alsa/ucm2/codecs/cs35l56+cs42l43-spk
    audio_drop_noextract_pin || true
    echo "Reboot to revert. Speakers go silent again until upstream alsa-ucm-conf"
    echo "ships the cs35l56+cs42l43-spk UCM (>= 1.2.16)."
  else
    echo "Reboot to revert the firmware/topology changes. The HiFi UCM stays --"
    echo "it's shipped by alsa-ucm-conf >= 1.2.16, not by this module."
  fi
}

module_status_extra() {
  local fw_state="" prof="" kmsg cards dkms_state module_path
  kmsg="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"

  dkms_state="$(dkms status -m "$AUDIO_DKMS_NAME" -v "$AUDIO_DKMS_VERSION" \
    -k "$(uname -r)" 2>/dev/null || true)"
  module_path="$(modinfo -n snd-soc-sof-sdw 2>/dev/null || true)"
  if audio_kernel_predates_card; then
    printf '  kernel:   %sLinux %s predates 6.19: no machine driver matches this laptop'\''s codecs, so there are no speakers on this kernel; boot 7.2 or newer%s\n' \
      "$c_warn" "$(uname -r)" "$c_off"
  elif audio_kernel_fixed_upstream; then
    if [[ $module_path == */updates/dkms/* ]]; then
      printf '  kernel:   %supstream B9406CAA quirk present; redundant DKMS is still selected — update audio-fix and reboot%s\n' \
        "$c_warn" "$c_off"
    else
      printf '  kernel:   %supstream B9406CAA ghost-RT722 quirk active; DKMS not needed%s\n' \
        "$c_ok" "$c_off"
    fi
  elif [[ $dkms_state == *installed* && $module_path == */updates/dkms/* ]]; then
    printf '  DKMS:     %soverlay v%s installed for %s%s\n' \
      "$c_ok" "$AUDIO_DKMS_VERSION" "$(uname -r)" "$c_off"
  elif [[ $dkms_state == *installed* ]]; then
    printf '  DKMS:     %sinstalled, but modinfo resolves to %s; run depmod/reboot%s\n' \
      "$c_warn" "${module_path:--}" "$c_off"
  else
    printf '  DKMS:     %snot installed for running kernel %s%s\n' \
      "$c_warn" "$(uname -r)" "$c_off"
  fi
  if [[ $(pkg_manager) == pacman ]]; then
    if [[ -f $AUDIO_CHECK_HOOK && -x $AUDIO_CHECK ]]; then
      printf '  check:    %spacman warns when a kernel update leaves the overlay unbuilt%s\n' \
        "$c_ok" "$c_off"
    else
      printf '  check:    %spost-update overlay check not installed; reinstall audio-fix%s\n' \
        "$c_warn" "$c_off"
    fi
  fi
  if [[ $kmsg == *"Calibration applied"* || $kmsg == *"Tuning PID:"* ]]; then
    fw_state="${c_ok}cs35l56 tuning firmware loaded${c_off}"
  elif [[ $kmsg == *"FIRMWARE_MISSING"* ]]; then
    fw_state="${c_warn}cs35l56 FIRMWARE_MISSING -- no OEM bin/wmfw${c_off}"
  else
    fw_state="${c_dim}cs35l56 firmware state not in current boot log${c_off}"
  fi
  printf '  cs35l56:  %s\n' "$fw_state"
  local entry dst shadowing=0
  if cirrus_firmware_is_upstream; then
    for entry in "${FIRMWARE_FILES[@]}"; do
      dst="${entry#*:}"
      [[ -f $dst ]] && shadowing=1
    done
    if (( shadowing )); then
      printf '  firmware: %sbundled copies shadow linux-firmware; reinstall audio-fix to remove them%s\n' \
        "$c_warn" "$c_off"
    else
      printf '  firmware: %sfrom linux-firmware (no bundled copies)%s\n' "$c_ok" "$c_off"
    fi
  fi
  if command -v pacman >/dev/null 2>&1 && ! pacman -Q sof-firmware >/dev/null 2>&1; then
    printf '  SOF:      %ssof-firmware is not installed; no SOF firmware/topology, so no card%s\n' \
      "$c_warn" "$c_off"
  fi

  # PipeWire's "Dummy Output" is not a UCM/profile problem: it means the
  # kernel never registered an ALSA card. Previously status printed no card
  # line at all in that case, which made a successful file install look like a
  # successful audio fix. Detect it before asking users to restart WirePlumber.
  cards="$(cat /proc/asound/cards 2>/dev/null || true)"
  if [[ -z $cards || $cards == *"no soundcards"* ]]; then
    printf '  card:     %sno ALSA sound card registered (PipeWire will show Dummy Output)%s\n' \
      "$c_warn" "$c_off"
    if grep -qF 'CODEC DAI cs35l56-ot25 not registered' <<<"$kmsg"; then
      if [[ $dkms_state == *installed* ]]; then
        printf '  kernel:   %sLinux 7.2.11 OT25 regression from the current boot; reboot once to load overlay %s, which works around it%s\n' \
          "$c_warn" "$AUDIO_DKMS_VERSION" "$c_off"
      else
        printf '  kernel:   %sLinux 7.2.11 regression: the amps never register cs35l56-ot25; update audio-fix (overlay %s works around it) or move to 7.2.12 or later%s\n' \
          "$c_warn" "$AUDIO_DKMS_VERSION" "$c_off"
      fi
    elif grep -Eq 'SDW3-Playback-SimpleJack|sof_sdw.*(error -12|failed with error -12)' <<<"$kmsg"; then
      if [[ $dkms_state == *installed* ]]; then
        printf '  kernel:   %sghost RT722 failure is from the current boot; reboot once to load the installed DKMS fix%s\n' \
          "$c_warn" "$c_off"
      else
        printf '  kernel:   %sghost RT722 duplicate-link failure detected; install/update audio-fix%s\n' \
          "$c_warn" "$c_off"
      fi
    else
      printf '  kernel:   %sinspect: journalctl -k -b | grep -Ei "sof|soundwire|cs35|cs42|snd"%s\n' \
        "$c_dim" "$c_off"
    fi
    return
  fi

  if command -v pactl >/dev/null 2>&1; then
    prof="$(pactl list cards 2>/dev/null | awk -F'Active Profile: ' '/Active Profile/ {print $2; exit}')"
    if [[ $prof == HiFi* ]]; then
      printf '  card:     %sActive Profile = HiFi (proper Speaker/Headphone routing)%s\n' "$c_ok" "$c_off"
    elif [[ -n $prof ]]; then
      printf '  card:     %sActive Profile = %s (expected HiFi -- restart WirePlumber)%s\n' "$c_warn" "$prof" "$c_off"
    else
      printf '  card:     %sALSA card exists, but PipeWire exposes no active card profile%s\n' "$c_warn" "$c_off"
    fi
  fi
}
