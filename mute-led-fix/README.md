# Mute indicator LEDs (F1 / F4)

On the ASUS ExpertBook Ultra B9406CAA, audio mute can work while the orange
F1 speaker and F4 microphone indicators do not follow it. This module adds
the missing speaker LED and an optional desktop-session synchronizer.

Verified on **BIOS B9406CAA.312, Arch Linux 7.2.3-arch1-3, Omarchy with
PipeWire and EasyEffects**. The laptop owner physically confirmed that both
lights turn on when muted and off when unmuted after installing the fix.
Other BIOS versions and desktops have not been hardware-tested.

## What is missing

The stock `asus-wmi` driver exposes `platform::micmute` via ASUS WMI device
`0x00040017`, but does not expose the speaker mute LED on this machine.
The B9406CAA.312 DSDT provides `0x0004001c` for the speaker indicator:

- DSTS returns `GGOV(0x001a0885) | 0x00010000` (presence and current state).
- DEVS passes boolean 0/1 to `SGOV(0x001a0885, value)` and returns 1.
- The microphone device similarly uses GPIO `0x001a0884`.

These are descriptions of the firmware's existing methods, **not instructions
to write GPIOs directly**. The driver calls the exported ASUS WMI API only.
The firmware table used for this analysis was compared byte-for-byte against
the running machine's DSDT. The speaker device ID is also named `SoundMuteLed`
in [G-Helper's ASUS interface](https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs).

The small GPL-2.0-only DKMS driver registers `platform::mute` with
`default_trigger = "audio-mute"`, the same trigger upstream uses. It is
restricted to this DMI product name, checks firmware presence, and refuses a
conflicting LED name. `BUILD_EXCLUSIVE_KERNEL` stops the build on 7.4 and
later, where the native LED is queued. It leaves the stock microphone driver
in charge of F4.

The unprivileged session service can reconcile speaker mute, microphone mute,
or both, once a second, using `brightnessctl` and logind. It does not change
permissions or audio state. Readback is compared before writing.

`MUTE_LED_SPEAKER` and `MUTE_LED_MIC` are independent. Each is `auto`
(default), `on`, or `off`. `auto` writes an LED only while its trigger is
`none`, so the service does not fight the kernel `audio-mute` or
`audio-micmute` trigger. Suspend/resume has not been tested with this service.

## Install

Prerequisites: DKMS, a kernel build toolchain, matching headers for the running
kernel, Python 3, `pactl`, `brightnessctl`, systemd/logind, and a desktop audio
server implementing the PulseAudio protocol (including `pipewire-pulse`).

For Arch's standard `linux` kernel, the additional packages are usually:

```sh
sudo pacman -S --needed dkms base-devel linux-headers python libpulse brightnessctl
```

Use your kernel's matching header package instead of `linux-headers` for LTS,
Zen or CachyOS, and the matching LLVM toolchain for a Clang-built kernel.
Built and loaded on 7.2.3-arch1-3. Not built on 7.4 or newer. DKMS's normal
kernel build settings apply; compiler overrides can be supplied through DKMS
config.

```sh
./patch.sh install mute-led-fix
```

No reboot required on a kernel that still needs the bridge. The installer
builds for the running kernel when that kernel is older than 7.4 and
`platform::mute` is not already provided by another driver. A registered
0.2 tree that differs from this checkout is not overwritten. DKMS version
0.1, from the previous revision of this module, is removed first.

The session service is not enabled by the installer. As your desktop user:

```sh
systemctl --user daemon-reload
systemctl --user enable --now expertbook-mute-leds.service
```

Force one LED from userspace, and leave the other to its kernel trigger, with
a user drop-in:

```ini
[Service]
Environment=MUTE_LED_SPEAKER=on
Environment=MUTE_LED_MIC=off
```

`on` writes the LED even when a kernel trigger is selected, which competes
with that trigger. Prefer `auto` unless you have set the trigger to `none`.

### Which audio state is shown?

When speaker sync is enabled, Omarchy uses `omarchy-audio-output-sink`, the
same helper as the volume/mute shortcut, so an EasyEffects DSP sink resolves
to its physical output. Other desktops use `pactl get-default-sink`. That
helper is the only Omarchy-specific part. Microphone sync follows the default
source.

Virtual inputs such as EasyEffects and their underlying hardware can have
separate mute states. F4 reports the default source's mute flag, not a guarantee
that every microphone is muted. The service does not change routing, hardware
mute, volume, or keybindings. Zero volume alone is not treated as mute.

## Verify

```sh
./patch.sh status mute-led-fix
systemctl --user status expertbook-mute-leds
journalctl --user -u expertbook-mute-leds
brightnessctl -d platform::mute info
brightnessctl -d platform::micmute info
```

Press the usual speaker/microphone mute shortcuts and also change mute through
your audio panel. The corresponding orange light should follow within about
one second. No root password should be needed for normal operation.

Verification performed on the reference machine (Omarchy, BIOS B9406CAA.312,
Linux 7.2.3-arch1-3):

- Built the DKMS driver against the running kernel, installed and loaded it.
- Wrote each LED on/off as the desktop user and read both states back.
- Deliberately desynchronized each LED without changing audio; the service
  restored the expected state automatically.
- The laptop owner confirmed both physical F1 and F4 indicators.
- No non-Omarchy desktop was tested. Suspend and resume were not tested.

For contributors, run `python -m unittest discover -s mute-led-fix/tests` for
the synchronizer's routing and write-suppression tests.

## Uninstall

```sh
./patch.sh uninstall mute-led-fix
```

Uninstall disables and stops `expertbook-mute-leds.service` for each user
with a running session, and removes that user's enablement links under both
`graphical-session.target.wants` and `default.target.wants`. If a user is not
logged in, the patcher prints the `systemctl --user disable --now` command
instead of claiming the service was stopped. The loaded LED driver remains
until the next reboot. DKMS 0.1 and 0.2 and their source trees are removed.
The stock microphone driver stays intact.

## Upstream path

This is a bridge for kernels before 7.4. Upstream has queued `platform::mute`
with an `audio-mute` default trigger for 7.4, so the DKMS module is not built
there. If `platform::mute` already exists and this module did not create it,
install still publishes the synchronizer and does not load the DKMS driver.
No claim is made that the queued kernel patch is in a release this machine is
running.
