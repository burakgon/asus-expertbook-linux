# Upstream patches

Three submission-ready patches that bring this ASUS B9406CAA into the
existing upstream quirk infrastructure — same shape as the entries
already shipped for Dell, Lenovo, and other ASUS models.

When all three land upstream, the corresponding modules in this repo
(`display-fix`, `audio-fix`, `touchpad-fix`) become redundant and
deletable.

## The three patches

### `0001-drm-i915-Add-Panel-Replay-quirk-for-ASUS-ExpertBook-.patch`

- **Tree:** `torvalds/linux` → `drivers/gpu/drm/i915/display/intel_quirks.c`
- **Mailing list:** `intel-xe@lists.freedesktop.org` (Cc: `intel-gfx@lists.freedesktop.org`)
- **What it does:** adds an `intel_dpcd_quirks[]` entry for PCI subsystem
  `0x1043:0x15e4` + panel sink IEEE OUI `0x00:0xaa:0x01` calling
  `quirk_disable_edp_panel_replay`. Same shape as the existing Dell XPS
  14 DA14260 entry. Reading `drm-intel-next` confirms upstream is also
  growing this list with more per-device disables (Dell XPS 16 DA16260
  recently added) — there is no "make Panel Replay actually work"
  upstream patch, even from Intel's own engineers ("disabled by default,
  at least until the underlying issue can be sorted out", per Phoronix
  for the Dell entry).
- **Replaces:** `display-fix` module's cmdline workaround.

### `0002-ASoC-Intel-sof_sdw-Add-quirk-for-ASUS-ExpertBook-Ult.patch`

- **Tree:** `torvalds/linux` → `sound/soc/intel/boards/sof_sdw.c`
- **Mailing list:** `linux-sound@vger.kernel.org` (Cc: `alsa-devel@alsa-project.org`)
- **What it does:** adds a `sof_sdw_ssid_quirk_table[]` entry for PCI
  subsystem `0x1043:0x15e4` flagging `SOC_SDW_SIDECAR_AMPS`. The SSID
  table is where ASUS Zenbook S14 / S16 and Lenovo P1 / P16 entries
  already live; ours fits in by ASUS subsystem-vendor sort order. Other
  ASUS entries use `SOC_SDW_CODEC_MIC` because they have only the
  CS42L43 codec; ours is structurally closer to Lenovo 0x3821
  (`SOC_SDW_SIDECAR_AMPS` only, cs42l43 + sidecar amps).
- **Unlike the Panel Replay one, this is a real "enable" patch** — once
  applied, ALSA UCM matches the resulting card to a HiFi profile and
  the speaker amps engage through the standard PipeWire path, with the
  F1 mute LED working again via UCM `SetLED` hooks.
- **Replaces:** the WirePlumber Pro Audio pin and the hand-written
  `cs42l43-spk+cs35l56/init.conf` UCM file in `audio-fix`.

### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` → `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab MR at <https://gitlab.freedesktop.org/libinput/libinput>
- **What it does:** disables `ABS_MT_PRESSURE` / `ABS_PRESSURE` for the
  PixArt I2C-HID `093A:4F05` haptic touchpad. Same shape as the Asus
  UX302LA quirk already in `50-system-asus.quirks`.
- **Replaces:** `touchpad-fix`'s `local-overrides.quirks`. The hwdb
  pressure-clamp file stays useful as belt-and-suspenders since not
  every libinput consumer reads `local-overrides.quirks` on every
  device-open path.

## Other research findings (not new patches, but relevant)

| Question | Finding |
|---|---|
| Is there a `sof_sdw` patch elsewhere in mainline that might already match us by SSID? | No. Searched master + drm-intel-next + linux-next. `0x15e4` / `B9406CAA` / `EXPERTBOOK` appear nowhere in upstream kernel. |
| Is there a kernel-level "make Panel Replay work on Dell" patch we missed? | No. Confirmed by reading `drm-intel-next` `intel_quirks.c` — that branch is *adding more* per-device disable entries (Dell XPS 16 DA16260), not enabling Panel Replay. Phoronix coverage of the Linux 7.1 patch is explicit: "disabled by default, at least until the underlying issue can be sorted out". |
| Is there a generic upstream Wi-Fi 7 BE211 fix Omarchy bundles that we should mirror? | None visible in `iwlwifi/cfg/{sc,bz,dr}.c`, `iwlwifi/pcie/drv.c`, or `iwl-config.h` in mainline. Whatever Omarchy patches for "Wi-Fi 7 on Dell XPS 2026+" appears to be either pre-mainline or in a Cachy/Dell-specific branch we couldn't locate. Our `wifi-fix` module's tunables (iwlmld power_scheme, ASPM, TSO/GSO) are donanım-bağımsız anyway. |
| Has `linux-firmware-cirrus` shipped our subsystem ID? | **Yes, in `20260410-1` (extra/core repo).** Older `1:20260309-1` (cachyos epoch) does not. The newer package contains: `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.bin.zst` plus a `cs35l56-b0-dsp1-misc-104315e4.wmfw.zst` symlink → `cs35l56/CS35L56_Rev3.13.4.wmfw.zst`. The shipping content is byte-identical to the files audio-fix carries (verified via sha256). When CachyOS bumps their epoch to `1:20260410+`, the firmware blobs in `audio-fix/` become redundant and the module can shed them. |
| Does the panel firmware bug have a fix in upstream xe? | Not for our model. The `intel_psr.c` codepath that times out (`Timed out waiting PSR idle state`) has had several touch-ups in 6.18-6.20 but none gates by panel sink OUI / DPCD revision in a way that helps us. The cleanest fix remains the per-device disable our 0001 adds. |

## Hardware identifiers used

| Field | Value | Source |
|---|---|---|
| PCI audio subsystem | `0x1043:0x15e4` | `lspci -nnvk -d ::0403` |
| eDP panel sink IEEE OUI | `0x00 0xaa 0x01` | DPCD register 0x300 (read via `/dev/drm_dp_aux0`) |
| EDID manufacturer | `SDC` (Samsung Display Corp) | EDID bytes 8-9: `0x4c83` |
| EDID product code | `0x4217` | EDID bytes 10-11 (LE) |
| DMI sys_vendor | `ASUS` | `/sys/class/dmi/id/sys_vendor` |
| DMI product_name | `ASUS EXPERTBOOK B9406CAA` | `/sys/class/dmi/id/product_name` |
| Touchpad | `093A:4F05` (ACPI `ASCP1D80`) | `/proc/bus/input/devices` |

## How to test (without rebuilding the kernel)

The libinput patch needs no rebuild — just place the new section into
`/etc/libinput/local-overrides.quirks`. We already do that in
`touchpad-fix` (and `libinput quirks list /dev/input/event9` confirms
it's loaded).

The two kernel patches need a rebuild. The CachyOS kernel sources are
already cloned at `~/Developer/kernel-build/linux-cachyos/`. The
PKGBUILD's `prepare()` already loops over every `*.patch` in `source=`
and applies it, so adding our two patches to the source array is all
that's needed.

```sh
cd ~/Developer/kernel-build/linux-cachyos/linux-cachyos
cp ~/Developer/asus_expertboot_linux/upstream-patches/000{1,2}*.patch .
# Edit PKGBUILD: append the two filenames to the source=() array
# Then:
makepkg -si           # ~30-60 minutes; installs at the end
sudo reboot
# Boot and verify:
./patch.sh status display-fix      # cmdline marker no longer needed
./patch.sh status audio-fix        # Pro Audio pin no longer needed
```

If both work, remove our local workarounds and submit the patches to
their respective mailing lists.

## How to submit (once verified)

Each patch is in `git format-patch` body style. For the kernel:

```sh
git send-email --to=<list> --cc=<maintainers> upstream-patches/0001-...patch
```

(Configure `git send-email` first, or paste body into the mailing-list
webform.)

For libinput: fork on GitLab, branch, apply `0003-...patch`, push, MR.
