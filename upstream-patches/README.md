# Upstream status

Tracking and backport material for the ASUS ExpertBook Ultra B9406CAA: one fix
already in Linus' tree plus a stable-backport request for it, an asus-wmi
keyboard backlight quirk under review, a display quirk patch and issue draft, a
libinput quirk, a power-profiles-daemon fix, a libdisplay-info memory-safety
report, and a packaging request that would make `hdr-fix` unnecessary. One
proposed audio quirk turned out to be invalid.

Status rechecked on 2026-09-28 against `torvalds/linux` 7.3-rc5, the 7.2.8 and
6.18.54 stable releases and drm-intel-next `a8c17ccf`; `0006` and the Linux 7.3
note under `0004` were updated on 2026-11-11 against pdx86 `review-ilpo-next`
`5680519168f6`. Files meant for someone else's tracker (`*.md`, `*.txt`) are
drafts to be sent by the maintainer.

## Accepted upstream

### `0004-soundwire-dmi-quirks-Disable-ghost-rt722-on-ASUS-Exp.patch`

- **Upstream commit:**
  [`90af3209742d`](https://github.com/torvalds/linux/commit/90af3209742db61a7f9d7d054a16165818cfc6d8)
- **Tree:** `torvalds/linux` → `drivers/soundwire/dmi-quirks.c`
- **Author:** Charles Keepax, Cirrus Logic
- **Tracking issue:** [thesofproject/linux#5828](https://github.com/thesofproject/linux/issues/5828)
- **What it does:** matches ASUS board `B9406CAA` and applies the existing
  `ghost_realtek` address remap, causing SoundWire to discard the unfitted
  RT722 endpoint before the SOF machine driver builds duplicate DAI links.

The file here is the exact upstream commit patch, retained for distro/stable
backports. It first ships in Linux 7.3 (present since 7.3-rc1) and is still
absent from 7.2.8 (rechecked 2026-09-28), so 7.2.y kernels need `audio-fix`'s
DKMS overlay unless their distributor backported the commit. The commit has no
`Cc: stable` tag, while the same fix for the GX651AX (`6d49beec658f`, with
`Cc: stable # 7.2.x`) reached 7.2.8.
[`stable-request-7.2-ghost-rt722.txt`](stable-request-7.2-ghost-rt722.txt) asks
for it and the Zenbook Duo and Zephyrus Duo quirks in 7.2.y; all three apply
cleanly, in order, to v7.2.8 (and 90af3209742d also to v6.18.54). `audio-fix` 3.1.1
checks the installed `soundwire_intel` module — the one that links
`dmi-quirks.o` — for the B9406CAA marker per kernel: it builds DKMS only for
kernels that lack the upstream quirk and removes the overlay once all installed
kernels have it. (3.1.0 inspected `soundwire_bus`, which never carries the
marker.)

Linux 7.3 is now released, and stock 7.3.y kernels bring the card up without
the overlay: CachyOS 7.3.3 here, and openSUSE Tumbleweed 7.3.1 in
[#35](https://github.com/burakgon/asus-expertbook-linux/issues/35).

## Pending or experimental

### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` →
  `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab merge request at
  <https://gitlab.freedesktop.org/libinput/libinput>
- **What it does:** marks the PixArt I2C-HID `093A:4F05` haptic touchpad as a
  pressure pad (`AttrInputProp=+INPUT_PROP_PRESSUREPAD`), exactly as upstream
  did for the sister pad `093A:4811`
  ([MR 1504](https://gitlab.freedesktop.org/libinput/libinput/-/merge_requests/1504),
  libinput 1.32.0). Applies to libinput 1.32.0 and passes
  `libinput quirks validate`.
- **Root cause:** the pad's report descriptor gives Tip Pressure no Logical
  Maximum of its own, so it inherits the Y field's 2601; the kernel sets
  `INPUT_PROP_PRESSUREPAD` itself only for pads reporting Button Type 1.
- **Status:** never submitted (no libinput MR or issue mentions 4F05). Send
  once the property has been confirmed on the device, with a
  `sudo libinput record` of normal use attached. Until then `touchpad-fix`
  keeps the proven `AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;` override.
- **Local replacement:** `touchpad-fix`'s block in `local-overrides.quirks`.

### `0001-drm-i915-display-Pin-ASUS-ExpertBook-Ultra-B9406CAA-to-PSR1.patch`

- **Tree:** drm-intel-next → `drivers/gpu/drm/i915/display/intel_quirks.c`
  (applies to `a8c17ccf`, 2026-09-23)
- **Where to send:** intel-gfx / intel-xe, with a drm/xe issue; the issue text
  is drafted in [`drm-xe-issue-b9406-psr1.md`](drm-xe-issue-b9406-psr1.md).
- **What it does:** adds this laptop to the two quirk tables upstream already
  has: `QUIRK_DISABLE_EDP_PANEL_REPLAY` (DPCD quirk, subsystem `1043:15e4` +
  sink OUI `00:aa:01`, the Dell XPS 14/16 pattern since 7.1) and
  `QUIRK_DISABLE_PSR2` (PCI quirk, `0xb080` / `1043:15e4`, the Xiaomi Book Pro
  14 pattern since 7.2). Panel Replay caps are then never read and PSR2 is
  never set up, which leaves PSR1, the same result as `display-fix`'s
  `xe.enable_panel_replay=0 xe.enable_psr=1`.
- **Status:** not sent. Tested only through the equivalent module parameters;
  the quirk entries still need one built-kernel test.
- **Local replacement:** `display-fix`.

The earlier version of this patch disabled Panel Replay alone, which on this
panel drops `xe` into PSR2 selective update over DSC and paints garbage. The
VSC SDP readout false positive that 7.2 logs on HDR modesets is fixed upstream
by `fd2e337ba66f` ("drm/i915/dp: Handle VSC SDP revision 7 in unpack", in
drm-intel-next for 7.4).

### `0005-platform-profile-Don-t-read-an-emulated-power-saver-.patch`

- **Tree:** `upower/power-profiles-daemon` → `src/ppd-driver-platform-profile.c`
  plus an integration test (applies to main `09eeb34`)
- **Where to send:** GitLab merge request, text drafted in
  [`ppd-emulated-power-saver.md`](ppd-emulated-power-saver.md); related to
  [#187](https://gitlab.freedesktop.org/upower/power-profiles-daemon/-/issues/187).
- **What it does:** when the legacy `platform_profile_choices` lack a low-power
  option (on this laptop: `balanced performance`, the choices the SoC Power
  Slider and asus-wmi share), power-saver is emulated by writing `balanced`.
  The daemon then reads its own write back as a switch to balanced, so
  performance → power-saver lands on balanced. The patch ignores that read-back.
- **Status:** not sent. The new test fails on main every time and passes with
  the fix; full suite 129/129.
- **Local replacement:** `power-profile-bridge` (starts the daemon with
  `--block-driver=platform_profile`).

### `0006-platform-x86-asus-wmi-Add-keyboard-backlight-read-b.patch`

- **Author:** Sercan Gökmen ([#12](https://github.com/burakgon/asus-expertbook-linux/pull/12))
- **Tree:** `torvalds/linux` → `drivers/platform/x86/asus-wmi.{c,h}`,
  `drivers/platform/x86/asus-nb-wmi.c`. pdx86 moves these files to
  `drivers/platform/asus/` for the next merge window (`ef696e89f8`, in
  `review-ilpo-next` since 2026-11-10).
- **Sent to:** `platform-driver-x86@vger.kernel.org` (see `MAINTAINERS`,
  "ASUS NOTEBOOKS AND EEEPC ACPI/WMI EXTRAS DRIVERS").
- **Applies to:** master `df2908090cda`, v7.2.3 and pdx86 `for-next`
  `c339f4010dea` (with an offset). On `review-ilpo-next` `5680519168f6`, after
  the move, this file applies only once its paths are rewritten to
  `drivers/platform/asus/`; the posted v2 carries blob indexes and applies
  there with `git am -3`.
- **What it does:** adds a `kbd_led_no_readback` quirk and a DMI entry for the
  B9406CAA, so `kbd_led_get()` returns the driver's cached keyboard backlight
  level instead of overwriting it with the constant 0 the firmware query
  returns on this board. That 0 is why the KDE slider, UPower and
  `brightnessctl` read 0, why `systemd-backlight` restores a dark keyboard,
  and why the first Fn press after any read gives level 1.
- **Status:** under review. v1 was sent on 2026-10-22
  ([lore](https://lore.kernel.org/r/20261022-b4-asus-wmi-b9406caa-kbd-readback-v1-1-fb33ed98dd16@gmail.com)),
  v2 on 2026-10-30
  ([lore](https://lore.kernel.org/r/20261030-b4-asus-wmi-b9406caa-kbd-readback-v2-1-ca93bb9039f6@gmail.com),
  [patchwork](https://patchwork.kernel.org/project/platform-driver-x86/patch/20261030-b4-asus-wmi-b9406caa-kbd-readback-v2-1-ca93bb9039f6@gmail.com/)).
  Both make the same code change as the file here; v2 rewrites the commit
  message, with the subject "platform/x86: asus-wmi: Skip keyboard backlight
  read-back on B9406CAA", and is based on pdx86 `for-next` `c339f4010dea`. No
  review replies yet, and not in `review-ilpo-next` as of 2026-11-11.
- **Related:** a patch for the ROG Strix G814FP
  ([v3](https://lore.kernel.org/r/20261110-asus-wmi-kbd-readback-v3-1-646adf2b8629@proton.me))
  adds a `kbd_led_no_wmi` quirk to the same `struct quirk_entry` and DMI
  table. The two do not depend on each other; whichever lands second needs a
  trivial rebase.
- **Local replacement:** none; `keyboard-backlight-auto` only writes the LED
  and does not need the read-back. The DKMS overlay from #12 (a patched copy
  of the whole `asus-wmi`/`asus-nb-wmi` per kernel series) is not shipped
  here: it would replace the platform driver that fan profiles, charge limits
  and `power-profile-bridge` depend on with a snapshot of one stable release.

## Drafts for other trackers

- [`libdisplay-info-displayid2-oob.md`](libdisplay-info-displayid2-oob.md):
  a report for libdisplay-info (already public here, so file it promptly). Since 788c056, a checksum-valid
  EDID with one oversized DisplayID v2 data block makes the parser read past the
  end of the EDID buffer (reproduced with AddressSanitizer on main `62a9346`),
  and failing data blocks leak. `hdr-fix/patches/0008` and `0009` fix both, apply
  to main and pass its 69 tests.

- [`arch-libdisplay-info-0.4.0.md`](arch-libdisplay-info-0.4.0.md): asks Arch to
  ship libdisplay-info 0.4.0, which reads HDR metadata from DisplayID 2.0 and
  would make `hdr-fix` unnecessary.

## Retired: the former `0002` sidecar-amplifier patch

The old patch added `SOC_SDW_SIDECAR_AMPS` for PCI subsystem `1043:15e4`.
It has been removed because this B9406CAA is not a SoundWire sidecar-amplifier
design. Upstream Cirrus analysis in
[SOF issue #5828](https://github.com/thesofproject/linux/issues/5828) identified
the firmware-described ghost RT722 as the kernel failure and warned that the
sidecar flag would produce the wrong component/UCM description.

No kernel SSID quirk is needed for the speaker routing:

- the permanent kernel fix is the accepted SoundWire DMI quirk above;
- the combined CS42L43 + CS35L56 UCM is already shipped by
  `alsa-ucm-conf >= 1.2.16`;
- the `1043:15e4` CS35L56 tuning is already shipped by current
  `linux-firmware-cirrus`.

## Hardware identifiers

| Field | Value |
|---|---|
| PCI audio subsystem | `1043:15e4` |
| eDP panel sink IEEE OUI | `00:aa:01` |
| EDID manufacturer / product | `SDC` / `0x4217` |
| DMI sys vendor / board | `ASUS` / `B9406CAA` |
| Touchpad | `093A:4F05` (ACPI `ASCP1D80`) |

## Verification

```sh
./patch.sh status audio-fix
./patch.sh status display-fix
cat /proc/asound/cards
journalctl -k -b | grep -Ei 'sof|soundwire|cs35|cs42|PSR|DSB|pageflip'
```

For kernels with the accepted SoundWire commit, `audio-fix` reports
`upstream B9406CAA ghost-RT722 quirk active` and no current-kernel DKMS module
is expected. On older kernels it reports the board-scoped DKMS overlay.
