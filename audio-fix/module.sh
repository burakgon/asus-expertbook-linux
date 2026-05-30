# audio-fix module manifest. Sourced by ../patch.sh.
#
# Restores full speaker + headphone audio on the ASUS ExpertBook Ultra B9406CAA
# (PCI subsystem 1043:15e4) through the proper ALSA UCM "HiFi" profile.
#
#   1) cs35l56 amps need OEM tuning firmware (.bin tuning + .wmfw patch,
#      ROM 3.4.4 -> 3.13.4). linux-firmware-cirrus >= 20260519 now ships these
#      upstream for 1043:15e4; the bundled blobs here are a fallback for older
#      linux-firmware (same filenames the driver looks for).
#
#   2) The card reports a combined sidecar-amp speaker codec
#      ("spk:cs35l56+cs42l43-spk", or two "spk:" tags on older kernels). Stock
#      alsa-ucm-conf 1.2.15.x has no UCM for it AND its SpeakerCodec regex drops
#      the trailing "-spk", so the UCM fails to open and PipeWire falls back to
#      an unrouted "stereo-fallback" profile that plays to the Jack PCM, not the
#      speakers. We install the upstream alsa-ucm-conf master files (Syntax 7):
#      sof-soundwire.conf (fixed regex) + the cs35l56+cs42l43-spk /
#      cs42l43-spk+cs35l56 speaker confs + the combined codec init. The UCM then
#      brings up a real HiFi profile: Speaker (hw:,2), Headphones (auto-switch on
#      jack), Headset/Internal Mic, HDMI 1-3, with working volume + mic-mute LED.
#
#   3) The generic SOF topology declares an unused SSP2-BT hardware-offload PCM
#      with no firmware blob; WirePlumber's probe of it spams the kernel log
#      (~40% of all kernel errors at boot). 52-disable-bt-sco-offload.conf
#      disables that node. Bluetooth audio (A2DP music + HFP calls) keeps
#      working over the normal PipeWire software path.
#
# This replaces the old "pro-audio profile pin" workaround (<= v1.3.0). HiFi is
# the correct approach: headphone jack auto-switching, named ports, and it
# becomes native once Arch ships alsa-ucm-conf >= 1.2.16 (then this module is
# firmware-only). NOTE: the speaker (F1) mute LED cannot be fixed from Linux on
# this laptop -- it exposes no speaker-mute LED device, only platform::micmute
# (which the HiFi UCM does drive).

MODULE_NAME="audio-fix"
MODULE_DESC="ASUS ExpertBook Ultra (B9406CAA) speaker/headphone audio via HiFi UCM + cs35l56 firmware"
MODULE_VERSION="2.0.0"

MODULE_FILES=(
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u0.wmfw"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.bin:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.bin"
  "cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw:/lib/firmware/cirrus/cs35l56-b0-dsp1-misc-104315e4-l2u1.wmfw"
  "sof-soundwire.conf:/usr/share/alsa/ucm2/sof-soundwire/sof-soundwire.conf"
  "cs35l56+cs42l43-spk.conf:/usr/share/alsa/ucm2/sof-soundwire/cs35l56+cs42l43-spk.conf"
  "cs42l43-spk+cs35l56.conf:/usr/share/alsa/ucm2/sof-soundwire/cs42l43-spk+cs35l56.conf"
  "cs42l43-spk+cs35l56-init.conf:/usr/share/alsa/ucm2/codecs/cs42l43-spk+cs35l56/init.conf"
  "52-disable-bt-sco-offload.conf:/etc/wireplumber/wireplumber.conf.d/52-disable-bt-sco-offload.conf"
)

module_post_install() {
  # Recent kernels request the codec init under "cs35l56+cs42l43-spk"; older
  # ones (two spk: tags) under "cs42l43-spk+cs35l56". Symlink so both resolve.
  ln -sfn cs42l43-spk+cs35l56 /usr/share/alsa/ucm2/codecs/cs35l56+cs42l43-spk

  # Pin our sof-soundwire.conf so an alsa-ucm-conf upgrade doesn't revert the
  # SpeakerCodec regex fix. Drop this once Arch ships alsa-ucm-conf >= 1.2.16.
  if ! grep -q "ucm2/sof-soundwire/sof-soundwire.conf" /etc/pacman.conf; then
    sed -i '/^#NoExtract/a NoExtract   = usr/share/alsa/ucm2/sof-soundwire/sof-soundwire.conf' /etc/pacman.conf
  fi

  echo "Run 'systemctl --user restart wireplumber' (or reboot) so the HiFi UCM"
  echo "loads. Default sink becomes '...sof_sdw.HiFi__Speaker__sink'."
}

module_post_uninstall() {
  rm -f /usr/share/alsa/ucm2/codecs/cs35l56+cs42l43-spk
  sed -i '\#ucm2/sof-soundwire/sof-soundwire.conf#d' /etc/pacman.conf 2>/dev/null || true
  echo "Reboot to revert. Speakers go silent again until upstream alsa-ucm-conf"
  echo "ships the cs35l56+cs42l43-spk UCM (>= 1.2.16)."
}

module_status_extra() {
  local fw_state="" prof="" kmsg
  kmsg="$(journalctl -k -b 0 --no-pager 2>/dev/null || true)"
  if [[ $kmsg == *"Calibration applied"* ]]; then
    fw_state="${c_ok}cs35l56 firmware patched, calibration applied${c_off}"
  elif [[ $kmsg == *"FIRMWARE_MISSING"* ]]; then
    fw_state="${c_warn}cs35l56 FIRMWARE_MISSING -- no OEM bin/wmfw${c_off}"
  else
    fw_state="${c_dim}cs35l56 firmware state not in current boot log${c_off}"
  fi
  printf '  cs35l56:  %s\n' "$fw_state"

  if command -v pactl >/dev/null 2>&1; then
    prof="$(pactl list cards 2>/dev/null | awk -F'Active Profile: ' '/Active Profile/ {print $2; exit}')"
    if [[ $prof == HiFi* ]]; then
      printf '  card:     %sActive Profile = HiFi (proper Speaker/Headphone routing)%s\n' "$c_ok" "$c_off"
    elif [[ -n $prof ]]; then
      printf '  card:     %sActive Profile = %s (expected HiFi -- restart WirePlumber)%s\n' "$c_warn" "$prof" "$c_off"
    fi
  fi
}
