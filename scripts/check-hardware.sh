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

# 6) Distro
printf '%sDistro%s\n' "$c_bold" "$c_off"
if [[ -f /etc/arch-release ]]; then
  ok "Arch (or derivative) — patcher's pacman + paths assumed correct"
elif command -v pacman >/dev/null 2>&1; then
  ok "$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,""); print $2}' /etc/os-release 2>/dev/null) — pacman present"
else
  warn "non-pacman distro — modules' files still apply, but intel-perf-fix's package install will need adapting"
fi
echo

# Summary
all_pass=1
[[ "$dmi_product" == "ASUS EXPERTBOOK B9406CAA" ]] || all_pass=0
[[ "$cpu" == *"Core(TM) Ultra"* ]] || all_pass=0

if (( all_pass == 1 )); then
  printf '%sResult: install-all is appropriate for this hardware.%s\n' "$c_ok" "$c_off"
  printf '\n  git clone https://github.com/burakgon/asus-expertbook-linux.git\n'
  printf '  cd asus-expertbook-linux\n'
  printf '  ./patch.sh install-all\n'
  printf '  sudo reboot\n\n'
else
  printf '%sResult: not a perfect match.%s Some modules may still help — pick à la carte\n' "$c_warn" "$c_off"
  printf 'with %s./patch.sh list%s and %s./patch.sh install <module>%s.\n\n' "$c_bold" "$c_off" "$c_bold" "$c_off"
fi
