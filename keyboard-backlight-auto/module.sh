# keyboard-backlight-auto module manifest.  ── OPTIONAL module ──
#
# Drives the keyboard backlight from the ambient light sensor, the way Windows
# and macOS do on this class of hardware. Without it the backlight only ever
# changes when you press the Fn keys or move the KDE slider.
#
# The control rules are not home-grown. Two shipping implementations supply
# them:
#
#   * The bucketized ambient light response (ALR) curve and the manual-override
#     lookup table are Microsoft's documented Windows 11 defaults for "Keyboard
#     Backlight Autobrightness" (Settings > Bluetooth & devices > Keyboard >
#     Keyboard backlight), reproduced verbatim including the registry string
#     format:
#     learn.microsoft.com/windows-hardware/design/component-guidelines/keyboard-backlight-implementation-guide
#
#     The curve is deliberately NOT monotonic. Counter-intuitively the keyboard
#     is dimmest-but-on in the dark (35% below 6 lux), brightest in the 40-100
#     lux range, and fully off above 200-300 lux. In true darkness a blazing
#     keyboard is glare against a dark-adapted eye; in a bright room the keycap
#     legends are readable by ambient light alone and backlighting only washes
#     out the contrast. Apple's "Computer light adjustment" patents (US7839379
#     and family) describe the simpler inverse relationship instead; we follow
#     Microsoft because it ships an exact, numeric, currently-maintained table.
#
#   * The reading smoothing is GNOME's, from gnome-settings-daemon
#     plugins/power/gsd-power-manager.c (iio_proxy_changed):
#         alpha = 1 / (1 + TIME_CONSTANT / dt)
#         acc   = alpha * reading + (1 - alpha) * acc
#     with TIME_CONSTANT = 1 / (2*pi * GSD_AMBIENT_BANDWIDTH_HZ), 0.1 Hz.
#
# Hysteresis needs no extra machinery: Microsoft's buckets overlap (bucket 1 is
# 0-6 lux, bucket 2 is 5-14, and so on), and the daemon stays in the bucket it
# is already in for as long as the reading remains inside that bucket's range.
# A reading hovering on a boundary therefore cannot flap between two levels.
#
# Machine-specific notes (ASUS ExpertBook Ultra B9406CAA):
#
#   * Writes to /sys/class/leds/asus::kbd_backlight/brightness reach the EC
#     across the whole 0..3 range, but reading that node back always returns 0 -
#     the firmware's query path is broken. The daemon never reads it; it tracks
#     what it last wrote. This is also why
#     systemd-backlight@leds:asus::kbd_backlight always saves 0 and restores a
#     dark keyboard at every boot; the service is ordered After= it so the
#     curve gets the last word.
#
#   * The Fn backlight keys emit NO input event - verified across all 15
#     /dev/input/event* devices while the keys were pressed. The "Asus WMI
#     hotkeys" device advertises KEY_KBDILLUMUP / KEY_KBDILLUMDOWN in its
#     capability bitmap only because asus-nb-wmi's sparse keymap declares them.
#
#     The kernel does report the change, through the LED class's
#     brightness_hw_changed attribute (POLLPRI) - that is how UPower notices and
#     relays BrightnessChangedWithSource(level, "internal"), which is what
#     raises KDE's on-screen display. That attribute carries the REAL level,
#     unlike `brightness`, so the daemon both detects an Fn press and learns
#     what the user chose. Verified 2026-09-02: levels 3 and 0 observed, each
#     starting a manual override.
#
#     The override still means "stop writing" rather than Microsoft's "hold
#     percentage X", because the level the user picked is theirs to keep until
#     the ambient reading leaves the override window.
#
#   * Lid handling is not part of either upstream spec; it is ours. With the
#     lid shut the keyboard is not visible, so the backlight is forced to 0.
#     The lid state comes from the Lid Switch evdev device, with
#     /proc/acpi/button/lid/*/state as the initial reading and fallback.

MODULE_NAME="keyboard-backlight-auto"
MODULE_DESC="Drive the keyboard backlight from the ambient light sensor (Windows 11 ALR curve)"
MODULE_VERSION="1.2.0"

MODULE_FILES=(
  "kbd-backlight-auto:/usr/local/bin/kbd-backlight-auto"
  "kbd-backlight-auto.service:/etc/systemd/system/kbd-backlight-auto.service"
  "kbd-backlight-auto.conf:/usr/share/kbd-backlight-auto/kbd-backlight-auto.conf"
)

_kba_conf=/etc/kbd-backlight-auto.conf

module_post_install() {
  # mod_install_files installs everything 0644; the daemon needs to be runnable
  # as a command too, not just via the unit's explicit python3 invocation.
  chmod 0755 /usr/local/bin/kbd-backlight-auto

  # The shipped config is a fully commented-out template, so seeding it is
  # cosmetic - but never clobber one the user has edited.
  if [[ -e $_kba_conf ]]; then
    echo "  keeping existing $_kba_conf (template at /usr/share/kbd-backlight-auto/)"
  else
    install -m 0644 /usr/share/kbd-backlight-auto/kbd-backlight-auto.conf "$_kba_conf"
    echo "  seeded $_kba_conf"
  fi

  systemctl daemon-reload
  systemctl enable --now kbd-backlight-auto.service
  # enable --now leaves an already-running daemon on the old code.
  systemctl restart kbd-backlight-auto.service

  echo
  echo "Done. The keyboard backlight now follows the ambient light sensor."
  echo "Watch it decide, without it touching the backlight:"
  echo "    sudo kbd-backlight-auto --probe -v"
}

module_post_uninstall() {
  systemctl disable --now kbd-backlight-auto.service 2>/dev/null || true
  systemctl daemon-reload

  echo
  echo "  $_kba_conf left in place (it may carry your edits). Remove with:"
  echo "    sudo rm $_kba_conf"
  echo "  The backlight keeps whatever level it had; set it with the Fn keys."
}

module_status_extra() {
  local state
  state="$(systemctl is-active kbd-backlight-auto.service 2>/dev/null || true)"
  case "$state" in
    active) printf '  service:               %sactive%s\n' "$c_ok" "$c_off" ;;
    *)      printf '  service:               %s%s%s\n' "$c_warn" "${state:-unknown}" "$c_off" ;;
  esac

  if systemctl is-enabled --quiet kbd-backlight-auto.service 2>/dev/null; then
    printf '  start at boot:         %senabled%s\n' "$c_ok" "$c_off"
  else
    printf '  start at boot:         %sdisabled%s\n' "$c_warn" "$c_off"
  fi

  if [[ -e $_kba_conf ]]; then
    printf '  config:                %s%s%s\n' "$c_ok" "$_kba_conf" "$c_off"
  else
    printf '  config:                %sabsent (built-in defaults)%s\n' "$c_dim" "$c_off"
  fi

  # Live sensor reading and the bucket it lands in, straight from the daemon.
  if [[ -x /usr/local/bin/kbd-backlight-auto ]]; then
    local reading
    reading="$(/usr/local/bin/kbd-backlight-auto --status 2>/dev/null \
               | sed -n 's/^reading: *//p')"
    [[ -n $reading ]] && printf '  ambient reading:       %s%s%s\n' "$c_dim" "$reading" "$c_off"
  fi

  local lid
  lid="$(cat /proc/acpi/button/lid/*/state 2>/dev/null | awk '{print $2}' | head -1)"
  [[ -n $lid ]] && printf '  lid:                   %s%s%s\n' "$c_dim" "$lid" "$c_off"
}
