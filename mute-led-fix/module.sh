# SPDX-License-Identifier: MIT
MODULE_NAME="mute-led-fix"
MODULE_DESC="F1 speaker and F4 microphone mute indicator LEDs"
MODULE_VERSION="1.2.0"

MODULE_FILES=(
  "b9406-mute-led.conf:/etc/modules-load.d/b9406-mute-led.conf"
  "sync.py:/usr/local/lib/asus-expertbook/mute-led-sync.py"
  "expertbook-mute-leds.service:/etc/systemd/user/expertbook-mute-leds.service"
)

MUTE_DKMS_NAME=b9406-mute-led
MUTE_DKMS_VERSION=0.3
# Earlier revisions of this module, oldest first: 0.1 had no kernel range,
# 0.2 accepted every 6.x kernel.
MUTE_DKMS_OLD_VERSIONS=(0.1 0.2)
MUTE_DKMS_ROOT=${MUTE_DKMS_ROOT:-/usr/src}
MUTE_DKMS_SOURCE=$MUTE_DKMS_ROOT/b9406-mute-led-$MUTE_DKMS_VERSION

# 7.4+ registers platform::mute itself. Before 6.19 asus-wmi does not export
# the devstate calls the bridge uses, and this laptop has no sound card for
# the LED to follow. Matches BUILD_EXCLUSIVE_KERNEL.
mute_kernel_needs_bridge() {
  local rel="${1:-$(uname -r)}"
  [[ $rel =~ ^(6\.19|7\.[0-3])\. ]]
}

mute_dkms_registered() {
  local version="$1" status=""
  command -v dkms >/dev/null 2>&1 || return 1
  status="$(dkms status -m "$MUTE_DKMS_NAME" -v "$version" 2>/dev/null || true)"
  [[ -n $status ]]
}

# State of version $1 on kernel $2: "installed", "built" or nothing.
mute_dkms_state() {
  local out
  out="$(dkms status -m "$MUTE_DKMS_NAME" -v "$1" -k "$2" 2>/dev/null || true)"
  case $out in
    *", $2, "*": installed"*) echo installed ;;
    *", $2, "*": built"*)     echo built ;;
  esac
}

mute_native_speaker_led() {
  [[ -e /sys/class/leds/platform::mute && ! -d /sys/module/b9406_mute_led ]]
}

# Installed kernels that still need the bridge. The running kernel drops out
# when it already shows a native platform::mute; older kernels installed next
# to a 7.4+ one stay in, so booting them keeps F1.
mute_bridge_kernels() {
  local k running
  running=$(uname -r)
  while IFS= read -r k; do
    mute_kernel_needs_bridge "$k" || continue
    [[ $k == "$running" ]] && mute_native_speaker_led && continue
    printf '%s\n' "$k"
  done < <(kernel_list)
}

mute_install_source() {
  local bundle="$MODULE_DIR/dkms/b9406-mute-led-$MUTE_DKMS_VERSION"
  [[ -f $bundle/dkms.conf ]] || die "[mute-led-fix] missing $bundle"
  rm -rf -- "$MUTE_DKMS_SOURCE"
  install -d -o root -g root -m 0755 "$MUTE_DKMS_SOURCE"
  install -o root -g root -m 0644 \
    "$bundle/b9406_mute_led.c" "$bundle/Makefile" "$bundle/dkms.conf" \
    "$MUTE_DKMS_SOURCE/"
  chmod -R go-w -- "$MUTE_DKMS_SOURCE"
  dkms add -m "$MUTE_DKMS_NAME" -v "$MUTE_DKMS_VERSION"
}

mute_remove_version() {
  local version="$1"
  local source="$MUTE_DKMS_ROOT/b9406-mute-led-$version"
  if mute_dkms_registered "$version"; then
    dkms remove -m "$MUTE_DKMS_NAME" -v "$version" --all
  fi
  rm -rf -- "$source"
}

# An earlier version stays only on a kernel that still needs the bridge and
# has no current build yet. It is taken off every other kernel and removed
# once no kernel runs it.
mute_retire_old_versions() {
  local k old
  local -a keep
  for old in "${MUTE_DKMS_OLD_VERSIONS[@]}"; do
    keep=()
    while IFS= read -r k; do
      [[ $(mute_dkms_state "$old" "$k") == installed ]] || continue
      if [[ " $* " == *" $k "* &&
            $(mute_dkms_state "$MUTE_DKMS_VERSION" "$k") != installed ]]; then
        keep+=("$k")
        continue
      fi
      dkms uninstall -m "$MUTE_DKMS_NAME" -v "$old" -k "$k"
    done < <(kernel_list)
    if (( ${#keep[@]} > 0 )); then
      warn "[mute-led-fix] kept $MUTE_DKMS_NAME $old on ${keep[*]}: $MUTE_DKMS_VERSION is not built there yet"
      continue
    fi
    mute_remove_version "$old"
  done
}

# A registered version whose tree differs from this checkout is left alone.
# Rebuilding it in place would replace a module root already compiled.
mute_ensure_dkms() {
  local bundle="$MODULE_DIR/dkms/b9406-mute-led-$MUTE_DKMS_VERSION" running k rc old
  local -a kernels=() built=() taken=()
  running=$(uname -r)

  mapfile -t kernels < <(mute_bridge_kernels)
  if (( ${#kernels[@]} == 0 )); then
    mute_remove_version "$MUTE_DKMS_VERSION"
    for old in "${MUTE_DKMS_OLD_VERSIONS[@]}"; do
      mute_remove_version "$old"
    done
    log "[mute-led-fix] no installed kernel needs the bridge (7.4+ has platform::mute, before 6.19 there is no card); DKMS bridge not installed"
    return 0
  fi

  if mute_dkms_registered "$MUTE_DKMS_VERSION"; then
    diff -rq "$bundle" "$MUTE_DKMS_SOURCE" >/dev/null ||
      die "[mute-led-fix] registered $MUTE_DKMS_NAME $MUTE_DKMS_VERSION differs from this checkout; remove it with: dkms remove -m $MUTE_DKMS_NAME -v $MUTE_DKMS_VERSION --all"
    chown -R root:root -- "$MUTE_DKMS_SOURCE"
    chmod -R go-w -- "$MUTE_DKMS_SOURCE"
  else
    mute_install_source
  fi

  # Every installed kernel that lacks the native LED, not only the running one:
  # booting another installed kernel must not lose F1 until DKMS next runs.
  # Compile first: nothing installed changes while a build can still fail.
  for k in "${kernels[@]}"; do
    if ! kernel_headers_present "$k"; then
      warn "[mute-led-fix] skipping $k: matching headers are not installed"
      continue
    fi
    case $(mute_dkms_state "$MUTE_DKMS_VERSION" "$k") in
      installed|built) built+=("$k"); continue ;;
    esac
    rc=0
    dkms build -m "$MUTE_DKMS_NAME" -v "$MUTE_DKMS_VERSION" -k "$k" || rc=$?
    if (( rc == 77 )); then
      log "[mute-led-fix] DKMS skipped $k"
      continue
    fi
    (( rc == 0 )) || return "$rc"
    built+=("$k")
  done

  # Swap kernel by kernel: an earlier version comes off a kernel only once the
  # current one is built for it, and goes back if the current one does not
  # install.
  for k in "${built[@]}"; do
    [[ $(mute_dkms_state "$MUTE_DKMS_VERSION" "$k") == installed ]] && continue
    taken=()
    for old in "${MUTE_DKMS_OLD_VERSIONS[@]}"; do
      [[ $(mute_dkms_state "$old" "$k") == installed ]] || continue
      dkms uninstall -m "$MUTE_DKMS_NAME" -v "$old" -k "$k"
      taken+=("$old")
    done
    rc=0
    dkms install -m "$MUTE_DKMS_NAME" -v "$MUTE_DKMS_VERSION" -k "$k" || rc=$?
    if (( rc != 0 )); then
      for old in "${taken[@]}"; do
        dkms install -m "$MUTE_DKMS_NAME" -v "$old" -k "$k" ||
          warn "[mute-led-fix] could not put $old back on $k"
      done
      return "$rc"
    fi
  done

  mute_retire_old_versions "${kernels[@]}"

  [[ " ${built[*]} " == *" $running "* ]] || return 0
  modprobe b9406_mute_led
}

mute_stop_user_sync() {
  local home name uid runtime wants
  local -a homes=()
  [[ -d /root ]] && homes+=(/root)
  for home in /home/*; do
    [[ -d $home ]] || continue
    homes+=("$home")
  done
  for home in "${homes[@]}"; do
    if [[ $home == /root ]]; then
      name=root
    else
      name=${home##*/}
    fi
    uid=$(id -u "$name" 2>/dev/null) || continue
    runtime=/run/user/$uid
    if [[ -S $runtime/systemd/private ]] && command -v runuser >/dev/null 2>&1; then
      if ! runuser -u "$name" -- env XDG_RUNTIME_DIR="$runtime" \
          systemctl --user disable --now expertbook-mute-leds.service; then
        warn "[mute-led-fix] could not stop expertbook-mute-leds for $name"
        warn "[mute-led-fix] as $name: systemctl --user disable --now expertbook-mute-leds.service"
      fi
    elif [[ -e $home/.config/systemd/user/graphical-session.target.wants/expertbook-mute-leds.service ||
            -e $home/.config/systemd/user/default.target.wants/expertbook-mute-leds.service ]]; then
      warn "[mute-led-fix] $name has the sync service enabled but no running user session"
      warn "[mute-led-fix] as $name: systemctl --user disable --now expertbook-mute-leds.service"
    fi
    for wants in \
      "$home/.config/systemd/user/graphical-session.target.wants/expertbook-mute-leds.service" \
      "$home/.config/systemd/user/default.target.wants/expertbook-mute-leds.service"
    do
      if [[ -e $wants || -L $wants ]]; then
        # As the user: the directories on the way are theirs, and root must
        # not follow a link planted in them.
        if runuser -u "$name" -- rm -f -- "$wants"; then
          log "[mute-led-fix] removed $wants"
        else
          warn "[mute-led-fix] could not remove $wants; as $name: rm $wants"
        fi
      fi
    done
  done
}

module_install() {
  local tool kernel bridge
  if [[ $(cat /sys/class/dmi/id/product_name) != "ASUS EXPERTBOOK B9406CAA" ]]; then
    warn "[mute-led-fix] only tested on ASUS EXPERTBOOK B9406CAA; skipping"
    return 10
  fi

  kernel=$(uname -r)
  # Only the optional session service needs these; the kernel triggers drive
  # both LEDs without it.
  for tool in python3 pactl brightnessctl; do
    command -v "$tool" >/dev/null ||
      warn "[mute-led-fix] missing $tool, which expertbook-mute-leds.service needs; see mute-led-fix/README.md prerequisites"
  done

  bridge="$(mute_bridge_kernels)"
  if [[ -n $bridge ]]; then
    for tool in dkms make; do
      command -v "$tool" >/dev/null || {
        warn "[mute-led-fix] missing $tool; see mute-led-fix/README.md prerequisites"
        return 1
      }
    done
  fi
  if grep -qxF -- "$kernel" <<<"$bridge"; then
    [[ -f /lib/modules/$kernel/build/Makefile ]] || {
      warn "[mute-led-fix] install matching headers for $kernel first"
      return 1
    }
  fi
  mute_ensure_dkms

  mod_install_files
  # The load entry stays while any installed kernel needs the bridge: on a
  # kernel without the module, systemd-modules-load logs it and carries on.
  if [[ -z $bridge ]]; then
    printf '%s\n' '# platform::mute is provided by the kernel; the DKMS module is not loaded.' \
      > /etc/modules-load.d/b9406-mute-led.conf
  fi
  echo "  Speaker and microphone sync are independent and off while a kernel trigger owns the LED."
  echo "  As your desktop user, enable only the LEDs you want userspace to drive:"
  echo "    systemctl --user daemon-reload"
  echo "    systemctl --user enable --now expertbook-mute-leds.service"
  echo "  Defaults are MUTE_LED_SPEAKER=auto and MUTE_LED_MIC=auto."
}

module_post_uninstall() {
  local old
  mute_stop_user_sync
  for old in "${MUTE_DKMS_OLD_VERSIONS[@]}"; do
    mute_remove_version "$old"
  done
  mute_remove_version "$MUTE_DKMS_VERSION"
  echo "  The loaded LED driver, if any, remains until the next reboot."
}

module_status_extra() {
  local led trigger
  for led in platform::mute platform::micmute; do
    if [[ -r /sys/class/leds/$led/brightness ]]; then
      # The file lists every trigger; the selected one is in brackets.
      trigger="$(grep -o '\[[^]]*\]' "/sys/class/leds/$led/trigger" 2>/dev/null | tr -d '[]' || true)"
      [[ -n $trigger ]] || trigger="?"
      printf '  %s brightness: %s\n' "$led" "$(<"/sys/class/leds/$led/brightness")"
      printf '    trigger: %s\n' "$trigger"
    else
      printf '  %s: absent\n' "$led"
    fi
  done
  command -v dkms >/dev/null && dkms status -m "$MUTE_DKMS_NAME" -v "$MUTE_DKMS_VERSION" || true
  echo "  Check sync as your desktop user: systemctl --user status expertbook-mute-leds"
}
