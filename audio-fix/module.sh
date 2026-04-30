# audio-fix module manifest. Sourced by ../patch.sh.
#
# Restores speaker audio on the ASUS ExpertBook Ultra B9406CAA (PCI subsystem
# 1043:15e4). Three problems get patched together:
#
#   1) cs35l56 amps boot in FIRMWARE_MISSING state. The OEM-specific .bin and
#      a matching .wmfw (firmware patch upgrading chip ROM 3.4.4 -> 3.13.4)
#      are bundled here. Calibration data already lives in the EFI variable
#      'CirrusSmartAmpCalibrationData' from the factory; once the wmfw lands
#      the driver applies it cleanly.
#
#   2) ALSA UCM lookup for codec dir 'cs42l43-spk+cs35l56' fails because the
#      directory does not exist upstream. We provide a minimal init.conf that
#      maps abstract speaker controls to the concrete AMPx switches and
#      attaches the platform 'speaker' LED to those switches.
#
#   3) Even with firmware loaded, WirePlumber selects the unrouted
#      'stereo-fallback' card profile. We pin the card to 'pro-audio' via a
#      drop-in /etc/wireplumber/wireplumber.conf.d rule, which exposes a
#      discrete Speaker sink (pro-output-2) PipeWire can route to. The first
#      time you log in after install you may need to right-click the speaker
#      sink in your DE and "set as default".
#
# F1 mute LED limitation: the SetLED bindings in the UCM init.conf only fire
# when a UCM HiFi profile is active. With pro-audio profile, the F1 LED stays
# in whatever state the EC firmware leaves it. Real fix waits for upstream
# alsa-ucm-conf + sof-soundwire to recognise the cs42l43-spk+cs35l56 codec
# combination and route through HiFi.conf.

MODULE_NAME="audio-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) cs35l56 speaker firmware + UCM + WP profile"
MODULE_VERSION="1.2.0"

MODULE_FILES=(
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw"
  "cs42l43-spk+cs35l56-init.conf:/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf"
  "51-asus-expertbook-pro-audio.conf:/etc/wireplumber/wireplumber.conf.d/51-asus-expertbook-pro-audio.conf"
)

module_post_install() {
  echo "Reboot recommended so the kernel reloads the cs35l56 firmware and"
  echo "WirePlumber re-evaluates the card profile from a clean state."
}

module_post_uninstall() {
  echo "Reboot to fully revert: speakers will go back to silent (FIRMWARE_MISSING)"
  echo "until upstream linux-firmware ships matching files for 1043:15e4."
}

module_status_extra() {
  local fw_state="" prof="" kmsg
  kmsg="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"
  if [[ $kmsg == *"Calibration applied"* ]]; then
    fw_state="${c_ok}firmware patched, calibration applied${c_off}"
  elif [[ $kmsg == *"FIRMWARE_MISSING"* ]]; then
    fw_state="${c_warn}FIRMWARE_MISSING — kernel can't find OEM bin/wmfw${c_off}"
  elif [[ $kmsg == *"cs35l56"* ]]; then
    fw_state="${c_warn}cs35l56 present but no calibration verdict yet${c_off}"
  else
    fw_state="${c_dim}cs35l56 not present in current-boot kernel log${c_off}"
  fi
  printf '  cs35l56:  %s\n' "$fw_state"

  if command -v pactl >/dev/null 2>&1; then
    prof="$(pactl list cards 2>/dev/null | awk '/Active Profile/ {print $3; exit}')"
    if [[ $prof == "pro-audio" ]]; then
      printf '  card:     %sActive Profile = pro-audio (Speaker exposed as pro-output-2)%s\n' "$c_ok" "$c_off"
    elif [[ -n $prof ]]; then
      printf '  card:     %sActive Profile = %s (expected pro-audio — restart WirePlumber after install)%s\n' "$c_warn" "$prof" "$c_off"
    fi
  fi
}
