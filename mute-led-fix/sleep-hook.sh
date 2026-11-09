#!/bin/sh
# SPDX-License-Identifier: MIT
# systemd-sleep hook: after resuming from hibernation, rewrite the F1 and F4
# mute LEDs from the current mute state.
#
# Resuming from hibernation passes through a firmware boot, which lights both
# LEDs. The restored kernel still holds the brightness it had before, and the
# audio-mute / audio-micmute triggers only write on a mute change, so the LEDs
# stay lit until the next toggle. Ordinary suspend is not affected.
#
# Never changes audio state. Called by systemd-sleep as: <pre|post> <sleep type>.
LEDS=${MUTE_LED_SYSFS:-/sys/class/leds}

[ "$1" = post ] || exit 0
case $2 in
  hibernate|hybrid-sleep|suspend-then-hibernate) ;;
  *) exit 0 ;;
esac

for led in platform::mute platform::micmute; do
  dir=$LEDS/$led
  [ -w "$dir/trigger" ] && [ -w "$dir/brightness" ] || continue
  # The trigger file lists every trigger; the selected one is in brackets.
  trigger=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$dir/trigger")
  if [ -n "$trigger" ] && [ "$trigger" != none ]; then
    # Attaching an audio trigger writes the current mute state to the LED.
    # Brightness is left as it is while the trigger is briefly detached.
    echo none > "$dir/trigger"
    echo "$trigger" > "$dir/trigger" ||
      echo "mute-led-fix: could not restore trigger $trigger on $led" >&2
  else
    # No trigger: write the current value back so it reaches the hardware.
    value=$(cat "$dir/brightness")
    echo "$value" > "$dir/brightness"
  fi
done
exit 0
