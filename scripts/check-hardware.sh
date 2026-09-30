#!/usr/bin/env bash
# Quick compatibility probe for the asus-expertbook-linux modules.
# Runs read-only — no sudo, no system changes.

set -u
c_ok=$'\033[32m'; c_err=$'\033[31m'; c_warn=$'\033[33m'
c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
[[ -t 1 ]] || { c_ok=""; c_err=""; c_warn=""; c_dim=""; c_bold=""; c_off=""; }

ok()    { printf '  %sOK%s   %s\n' "$c_ok" "$c_off" "$*"; }
warn()  { printf '  %sWARN%s %s\n' "$c_warn" "$c_off" "$*"; }
fail()  { printf '  %sFAIL%s %s\n' "$c_err" "$c_off" "$*"; }
note()  { printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }
log()   { note "$*"; }
die()   { fail "$*"; exit 1; }

# Report the platform exactly as the patcher resolves it. Run from a clone this
# uses lib/distro.sh itself; the README also documents this script as a
# `curl | bash` one-liner, where that file is not on disk, so the three probes
# it needs have a self-contained fallback below.
SCRIPT_DIR=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
fi
# shellcheck source=../lib/distro.sh
[[ -n $SCRIPT_DIR && -f "$SCRIPT_DIR/../lib/distro.sh" ]] && source "$SCRIPT_DIR/../lib/distro.sh"

if ! declare -F distro_family >/dev/null; then
  distro_family() {
    local id="" id_like="" token
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      id="$( { . /etc/os-release; printf '%s' "${ID:-}"; } 2>/dev/null || true )"
      # shellcheck disable=SC1091
      id_like="$( { . /etc/os-release; printf '%s' "${ID_LIKE:-}"; } 2>/dev/null || true )"
    fi
    # shellcheck disable=SC2086
    for token in $id $id_like; do
      case "$token" in
        arch)          echo arch;   return 0 ;;
        debian|ubuntu) echo debian; return 0 ;;
      esac
    done
    if command -v pacman >/dev/null 2>&1; then echo arch
    elif command -v dpkg-query >/dev/null 2>&1; then echo debian
    else echo unknown
    fi
  }
  pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then echo pacman
    elif command -v dpkg-query >/dev/null 2>&1; then echo apt
    else echo none
    fi
  }
  cmdline_backend() {
    if command -v limine-update >/dev/null 2>&1 ||
       command -v limine-mkinitcpio >/dev/null 2>&1; then echo limine
    elif command -v kernelstub >/dev/null 2>&1; then echo kernelstub
    elif [[ -f /etc/default/grub ]] &&
         { command -v update-grub >/dev/null 2>&1 ||
           command -v grub-mkconfig >/dev/null 2>&1; }; then echo grub
    else echo none
    fi
  }
fi

printf '%sasus-expertbook-linux — hardware compatibility probe%s\n\n' "$c_bold" "$c_off"

# 1) DMI laptop model
dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo '?')
dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo '?')
dmi_board=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo '?')

printf '%sLaptop model%s\n' "$c_bold" "$c_off"
if [[ "$dmi_product" == "ASUS EXPERTBOOK B9406CAA" ]]; then
  ok "$dmi_product (full match — every module fits)"
elif [[ "$dmi_product" == *EXPERTBOOK* ]]; then
  warn "$dmi_product — sibling ExpertBook model; touchpad/wifi/display may apply, audio firmware may not"
elif [[ "$dmi_vendor" == "ASUS"* ]]; then
  warn "$dmi_vendor / $dmi_product — different ASUS laptop; only generic modules likely apply"
else
  fail "$dmi_vendor / $dmi_product — not an ASUS laptop. The audio-fix firmware blobs definitely don't apply."
fi
echo

# 2) CPU family
cpu=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)
printf '%sCPU%s\n' "$c_bold" "$c_off"
if [[ "$cpu" == *"Core(TM) Ultra"* && "$cpu" == *"3"* ]]; then
  ok "$cpu (Panther Lake / Core Ultra Series 3)"
elif [[ "$cpu" == *"Core(TM) Ultra"* ]]; then
  warn "$cpu — Intel Core Ultra but possibly Lunar Lake / Meteor Lake. Some modules may still apply."
else
  fail "$cpu — not Panther Lake. Most kernel-level expectations of this repo won't hold."
fi
echo

# 3) Touchpad (PixArt 093A:4F05)
printf '%sTouchpad%s\n' "$c_bold" "$c_off"
if grep -qiE 'Vendor=093a Product=4f05' /proc/bus/input/devices 2>/dev/null; then
  ok "PixArt 093A:4F05 (ACPI ASCP1D80) — touchpad-fix applies directly"
else
  tp=$(awk '/^I:/ {i=$0} /^N:/{n=$0} /^H:/{if (n ~ /Touchpad/) print n}' /proc/bus/input/devices 2>/dev/null | head -1)
  if [[ -n "$tp" ]]; then
    warn "$tp — different touchpad; touchpad-fix may not apply"
  else
    note "no touchpad device detected"
  fi
fi
echo

# 4) Audio codec
printf '%sAudio (Cirrus CS42L43 + 2× CS35L56)%s\n' "$c_bold" "$c_off"
audio_subsys=$(lspci -nn -d ::0403 2>/dev/null | head -1 | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]' | tail -1 | tr -d '[]')
if [[ "$audio_subsys" == "8086:e428" ]] && lspci -vnn -d ::0403 2>/dev/null | grep -q '1043:15e4'; then
  ok "subsystem 1043:15e4 — audio-fix firmware blobs apply directly"
elif lspci -vnn -d ::0403 2>/dev/null | grep -q '1043:15'; then
  ssd=$(lspci -vnn -d ::0403 2>/dev/null | grep -oE 'Subsystem:.*\[1043:[0-9a-f]+\]' | head -1)
  warn "$ssd — sibling ASUS subsystem; may need its own firmware blobs"
else
  ssd=$(lspci -vnn -d ::0403 2>/dev/null | grep -oE 'Subsystem:.*\[[0-9a-f]+:[0-9a-f]+\]' | head -1)
  note "$ssd — different vendor; audio-fix not directly applicable"
fi
if grep -qi 'cs35l56\|cs42l43' /proc/asound/modules 2>/dev/null || lsmod | grep -qE 'cs35l56|cs42l43'; then
  ok "cs35l56 / cs42l43 driver loaded"
else
  warn "cs35l56 / cs42l43 driver not loaded"
fi
echo

# 5) Wi-Fi
printf '%sWi-Fi%s\n' "$c_bold" "$c_off"
wifi=$(lspci -nnvk -d ::0280 2>/dev/null | head -3 | grep -oE '\[8086:[0-9a-f]{4}\]' | head -1)
if [[ "$wifi" == "[8086:e440]" ]]; then
  ok "Intel Wi-Fi 7 BE211 (8086:e440) — wifi-fix applies directly"
elif [[ "$wifi" == \[8086:* ]]; then
  warn "$wifi — different Intel Wi-Fi card; wifi-fix may help (iwlwifi family)"
else
  note "no recognised Wi-Fi card"
fi
if lsmod | grep -q '^iwlmld'; then
  ok "iwlmld op_mode loaded (Wi-Fi 7 driver)"
elif lsmod | grep -q '^iwlmvm'; then
  warn "iwlmvm loaded — older Wi-Fi 6 driver, wifi-fix's iwlmld param won't apply"
fi
echo

# 6) Integrated Bluetooth
printf '%sBluetooth%s\n' "$c_bold" "$c_off"
if lspci -nn 2>/dev/null | grep -qi '\[8086:e476\]'; then
  ok "Intel Panther Lake CNVi Bluetooth (8086:e476) detected"
  if grep -RqsE '^[[:space:]]*(blacklist[[:space:]]+btintel_pcie|install[[:space:]]+btintel_pcie[[:space:]]+/bin/(true|false))' \
      /etc/modprobe.d 2>/dev/null; then
    fail "btintel_pcie is blacklisted in /etc/modprobe.d — remove the override to use the integrated controller"
  elif lspci -nnk -d 8086:e476 2>/dev/null | grep -q 'Kernel driver in use: btintel_pcie'; then
    ok "btintel_pcie driver active"
  elif grep -q '^btintel_pcie ' /proc/modules 2>/dev/null; then
    ok "btintel_pcie module loaded; controller may still be probing"
  else
    warn "btintel_pcie is not loaded"
  fi

  if command -v bluetoothctl >/dev/null 2>&1 && \
     timeout 3 bluetoothctl list 2>/dev/null | grep -q '^Controller '; then
    ok "BlueZ exposes an integrated controller"
  else
    warn "BlueZ does not currently expose a controller"
  fi
else
  note "Intel 8086:e476 controller not detected"
fi
echo

# 7) Fingerprint reader
printf '%sFingerprint%s\n' "$c_bold" "$c_off"
fingerprint=""
if command -v lsusb >/dev/null 2>&1; then
  fingerprint="$(lsusb 2>/dev/null | grep -i '2808:a97a' | head -1)"
fi
if [[ -n $fingerprint ]]; then
  ok "FocalTech FT9349 (2808:a97a) — supported by upstream libfprint 1.94.100+"
  if command -v pacman >/dev/null 2>&1; then
    fp_version="$(pacman -Q libfprint 2>/dev/null | awk '{print $2}')"
    fp_version="${fp_version%%-*}"
    if [[ -n $fp_version ]] && \
       [[ $(printf '%s\n%s\n' 1.94.100 "$fp_version" | sort -V | head -1) == 1.94.100 ]]; then
      ok "libfprint $fp_version installed — no custom Git package required"
    else
      warn "install/update the normal libfprint + fprintd packages (need libfprint 1.94.100+)"
    fi
  fi
  fp_dev="" fp_pwr="" fp_delay="" fp_runtime=""
  for d in /sys/bus/usb/devices/*; do
    if [[ -r "$d/idVendor" && -r "$d/idProduct" ]]; then
      if [[ "$(<"$d/idVendor")" == "2808" && "$(<"$d/idProduct")" == "a97a" ]]; then
        fp_dev="$d"
        [[ -r "$d/power/control" ]] && fp_pwr="$(<"$d/power/control")"
        [[ -r "$d/power/autosuspend_delay_ms" ]] && fp_delay="$(<"$d/power/autosuspend_delay_ms")"
        [[ -r "$d/power/runtime_status" ]] && fp_runtime="$(<"$d/power/runtime_status")"
        break
      fi
    fi
  done
  if [[ -z $fp_dev ]]; then
    note "FocalTech sysfs node not found"
  elif [[ $fp_pwr == on ]]; then
    ok "USB autosuspend disabled (control=on, delay_ms=${fp_delay:-?}, runtime=${fp_runtime:-?})"
  elif [[ $fp_delay == -* ]]; then
    ok "control=$fp_pwr but delay_ms=$fp_delay disables autosuspend (runtime=${fp_runtime:-?})"
  elif [[ $fp_runtime == suspended ]]; then
    warn "reader is suspended (control=$fp_pwr, delay_ms=$fp_delay, runtime=$fp_runtime); a scan can hang until it resumes"
  else
    warn "autosuspend is allowed (control=${fp_pwr:-?}, delay_ms=${fp_delay:-?}, runtime=${fp_runtime:-?}); a scan can hang if the reader suspends"
  fi
else
  note "FocalTech 2808:a97a not detected"
fi
echo

# 8) Camera UEFI firmware
printf '%sCamera firmware%s\n' "$c_bold" "$c_off"
camera_raw=""
if command -v fwupdmgr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  camera_raw="$(fwupdmgr get-devices --json 2>/dev/null | jq -r \
    'first(.Devices[] | select((.Guid // []) | index("d9d10946-36c2-3bcb-bffc-fcda56025390")) | (.VersionRaw // .Version // 0)) // 0' \
    2>/dev/null || true)"
fi
if [[ $camera_raw =~ ^[0-9]+$ ]] && (( camera_raw >= 479569 )); then
  ok "ASUS 3009 / 10.1.2.3009 baseline satisfied (ESRT raw $camera_raw)"
elif [[ $camera_raw =~ ^[0-9]+$ ]] && (( camera_raw > 0 )); then
  warn "ESRT raw $camera_raw is below verified 3009 baseline 479569 — camera-firmware will offer the update"
else
  note "version not available without fwupd + jq; run ./patch.sh status camera-firmware"
fi
echo

# 9) Intel Sensor Hub firmware (the ambient light sensor lives behind it)
printf '%sIntel Sensor Hub (ISH)%s\n' "$c_bold" "$c_off"
ish_pci=""
for d in /sys/bus/pci/devices/*; do
  [[ "$(cat "$d/vendor" 2>/dev/null)" == "0x8086" && "$(cat "$d/device" 2>/dev/null)" == "0xe445" ]] || continue
  ish_pci="${d##*/}"; break
done
if [[ -n $ish_pci ]]; then
  ish_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo '')
  ish_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo '')
  ish_name=""
  if command -v python3 >/dev/null 2>&1 && [[ -n $ish_vendor && -n $ish_product ]]; then
    ish_name="$(python3 -c 'import sys,zlib; print("ish_ptl_%08x_%08x.bin" % (zlib.crc32(sys.argv[1].encode()), zlib.crc32(sys.argv[2].encode())))' "$ish_vendor" "$ish_product" 2>/dev/null)"
  fi
  ish_clients=0
  for d in /sys/bus/ishtp/devices/*; do [[ -e $d ]] && ish_clients=$(( ish_clients + 1 )); done
  if (( ish_clients > 0 )); then
    ok "ISH $ish_pci (8086:e445) firmware running — $ish_clients ishtp client devices"
  elif [[ -n $ish_name && -f /lib/firmware/updates/intel/ish/$ish_name ]]; then
    warn "ISH $ish_pci: $ish_name is installed but no ishtp client devices yet — reboot (or reload intel_ish_ipc)"
  else
    warn "ISH $ish_pci: no ishtp client devices and no per-OEM image ${ish_name:-ish_ptl_<vendor>_<product>.bin} — ish-firmware applies (needed for the ambient light sensor)"
  fi
else
  note "no Intel Sensor Hub 8086:e445 on PCI — ish-firmware does not apply"
fi
echo

# 10) Ambient light sensor + keyboard backlight
printf '%sAmbient light sensor / keyboard backlight%s\n' "$c_bold" "$c_off"
als_dev=""
for d in /sys/bus/iio/devices/iio:device*; do
  [[ -r "$d/name" ]] || continue
  if [[ "$(cat "$d/name" 2>/dev/null)" == "als" && -r "$d/in_illuminance_raw" ]]; then
    als_dev="$d"; break
  fi
done
if [[ -n $als_dev ]]; then
  als_raw="$(cat "$als_dev/in_illuminance_raw" 2>/dev/null || echo 0)"
  als_scale="$(cat "$als_dev/in_illuminance_scale" 2>/dev/null || echo 1)"
  als_lux="$(awk -v r="$als_raw" -v s="$als_scale" 'BEGIN{printf "%.1f", r*s}')"
  ok "iio 'als' at ${als_dev##*/} reading ${als_lux} lux — keyboard-backlight-auto applies"
else
  note "no iio 'als' device — keyboard-backlight-auto has nothing to read (see the ISH line above; ish-firmware provides it)"
fi
if [[ -w /sys/class/leds/asus::kbd_backlight/brightness || -e /sys/class/leds/asus::kbd_backlight/brightness ]]; then
  ok "asus::kbd_backlight LED present (max $(cat /sys/class/leds/asus::kbd_backlight/max_brightness 2>/dev/null || echo '?'))"
  note "read-back always reports 0 on this firmware — expected, not a fault; see keyboard-backlight-fix"
else
  note "asus::kbd_backlight LED not present"
fi
echo

# 11) Distro
printf '%sDistro%s\n' "$c_bold" "$c_off"
pretty="$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,""); print $2}' /etc/os-release 2>/dev/null)"
case "$(distro_family)" in
  arch)
    ok "${pretty:-Arch (or derivative)} — pacman; every module is supported here"
    ;;
  debian)
    ok "${pretty:-Debian (or derivative)} — apt/dpkg"
    note "supported so far: intel-perf-fix, plus every module that only ships"
    note "files and units (touchpad-fix, wifi-fix, keyboard-backlight-auto)."
    note "The rest still assume Arch — see issue #4 for the port status."
    ;;
  *)
    warn "${pretty:-unknown distribution} — no supported package manager detected"
    note "file-only modules still apply; anything that installs packages will not"
    ;;
esac
note "package manager: $(pkg_manager)    boot parameters: $(cmdline_backend)"
echo

# Summary
all_pass=1
[[ "$dmi_product" == "ASUS EXPERTBOOK B9406CAA" ]] || all_pass=0
[[ "$cpu" == *"Core(TM) Ultra"* ]] || all_pass=0

if (( all_pass == 1 )); then
  # install-all is not harmless outside Arch. webcam-ai-fix declares no
  # module_install, so mod_install_files runs whatever the distro: it drops
  # /etc/modules-load.d/v4l2loopback.conf for a module Debian does not package,
  # leaving systemd-modules-load to fail at every boot, and its post-install
  # adds the invoking user to the render group. So name the ported modules here
  # rather than claim the Arch-only ones do nothing.
  if [[ "$(distro_family)" == arch ]]; then
    install_cmd='./patch.sh install-all'
    printf '%sResult: install-all is appropriate for this hardware.%s\n' "$c_ok" "$c_off"
  else
    install_cmd='./patch.sh install touchpad-fix wifi-fix keyboard-backlight-auto intel-perf-fix'
    printf '%sResult: the hardware matches. Install the ported modules, not install-all.%s\n' \
      "$c_ok" "$c_off"
    printf '%sinstall-all would also run the Arch-only modules. webcam-ai-fix still\n' "$c_dim"
    printf 'writes its modules-load.d and modprobe.d files and adds you to the render\n'
    printf 'group, even though v4l2loopback-dkms and obs-backgroundremoval cannot be\n'
    printf 'installed here. keyboard-backlight-fix is the harmless one: it skips itself\n'
    printf 'on every distro, superseded by keyboard-backlight-auto.%s\n' "$c_off"
  fi
  printf '\n  git clone https://github.com/burakgon/asus-expertbook-linux.git\n'
  printf '  cd asus-expertbook-linux\n'
  printf '  %s\n' "$install_cmd"
  printf '  sudo reboot\n\n'
else
  printf '%sResult: not a perfect match.%s Some modules may still help — pick à la carte\n' "$c_warn" "$c_off"
  printf 'with %s./patch.sh list%s and %s./patch.sh install <module>%s.\n\n' "$c_bold" "$c_off" "$c_bold" "$c_off"
fi
