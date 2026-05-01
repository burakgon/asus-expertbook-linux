# Upstream patches

Three patches that mirror the kind of vendor-specific fixes Omarchy ships
for Dell Panther Lake hardware, but for the ASUS ExpertBook Ultra
**B9406CAA** instead. Each one targets a different upstream tree.

When all three land upstream, the corresponding modules under this repo
(`display-fix`, `audio-fix`, `touchpad-fix`) become redundant and can be
uninstalled.

## The three patches

### `0001-drm-i915-Add-Panel-Replay-quirk-for-ASUS-ExpertBook-.patch`

- **Tree:** `torvalds/linux` → `drivers/gpu/drm/i915/display/intel_quirks.c`
- **Mailing list:** `intel-xe@lists.freedesktop.org` (Cc: `intel-gfx@lists.freedesktop.org`)
- **Maintainers:** Jani Nikula, Rodrigo Vivi, Joonas Lahtinen
- **What it does:** adds an `intel_dpcd_quirks[]` entry for PCI subsystem
  `0x1043:0x15e4` + panel sink IEEE OUI `0x00:0xaa:0x01` that triggers
  `quirk_disable_edp_panel_replay`. Mirrors the existing Dell XPS 14
  DA14260 entry directly above it.
- **Replaces in this repo:** `display-fix` module's cmdline workaround.

### `0002-ASoC-Intel-sof_sdw-Add-quirk-for-ASUS-ExpertBook-Ult.patch`

- **Tree:** `torvalds/linux` → `sound/soc/intel/boards/sof_sdw.c`
- **Mailing list:** `linux-sound@vger.kernel.org` (Cc: `alsa-devel@alsa-project.org`)
- **Maintainers:** Pierre-Louis Bossart, Bard Liao, Mark Brown
- **What it does:** adds a `sof_sdw_quirk_table[]` DMI entry for ASUS
  ExpertBook B9406CAA setting `SOC_SDW_SIDECAR_AMPS` — same flag the
  existing Dell SKU `0DD6` entry uses, because the codec topology is the
  same (CS42L43 + 2× CS35L56 sidecar amps).
- **Replaces in this repo:** the UCM `cs42l43-spk+cs35l56/init.conf`
  override and most of the `audio-fix` WirePlumber pinning. The OEM
  firmware blobs in `audio-fix/` are still needed until upstream
  `linux-firmware` ships the per-OEM `cs35l56-b0-dsp1-misc-104315e4-l2u{0,1}.{wmfw,bin}`
  files (separate effort).

### `0003-libinput-quirks-Add-PixArt-093A-4F05-touchpad.patch`

- **Tree:** `freedesktop.org/libinput/libinput` → `quirks/30-vendor-pixart.quirks`
- **Where to send:** GitLab MR at <https://gitlab.freedesktop.org/libinput/libinput>
- **Maintainer:** Peter Hutterer
- **What it does:** disables `ABS_MT_PRESSURE` / `ABS_PRESSURE` for the
  PixArt I2C-HID `093A:4F05` haptic touchpad. Same shape as the Asus
  UX302LA quirk already shipped in `50-system-asus.quirks`.
- **Replaces in this repo:** `touchpad-fix`'s libinput
  `local-overrides.quirks`.

## How to test before submitting

The libinput patch can be applied **without rebuilding anything** —
copy the new section into a local libinput build's `quirks/` directory,
or just place the same content at
`/etc/libinput/local-overrides.quirks`. We already do that in
`touchpad-fix`.

The two kernel patches need a kernel rebuild. Either:

1. **Build a CachyOS kernel locally** with the patches applied:
   ```sh
   git clone https://github.com/CachyOS/linux-cachyos
   cd linux-cachyos/linux-cachyos
   # add 0001-...patch and 0002-...patch to source=() and prepare()
   makepkg -si
   ```

2. **Or build mainline directly:**
   ```sh
   git clone --depth=1 https://github.com/torvalds/linux
   cd linux
   patch -p1 < /path/to/0001-drm-i915-Add-Panel-Replay-quirk-for-ASUS-ExpertBook-.patch
   patch -p1 < /path/to/0002-ASoC-Intel-sof_sdw-Add-quirk-for-ASUS-ExpertBook-Ult.patch
   # zcat /proc/config.gz > .config && make olddefconfig
   make -j$(nproc) && sudo make modules_install install
   ```

Once boot-tested, remove our local workarounds and reboot to confirm
the upstream-style fix carries the load. If everything stays good for a
few days of normal use, send the patches.

## How to submit

Each patch is in `git format-patch` style — sender name, subject, body,
trailers, diff.

```sh
git send-email \
  --to=<list> \
  --cc=<maintainers> \
  upstream-patches/0001-...patch
```

Configure `git send-email` first (`git config sendemail.smtpserver ...`),
or paste the patch body into the mailing-list webform.

For libinput, fork on GitLab, create a branch, apply `0003-...patch`,
push, open a Merge Request.

## Hardware identifiers used

For reference / future maintainers:

| Field | Value | Source |
|---|---|---|
| PCI audio subsystem | `0x1043:0x15e4` | `lspci -nnvk -d ::0403` |
| eDP panel sink IEEE OUI | `0x00 0xaa 0x01` | DPCD register 0x300 (read via `/dev/drm_dp_aux0`) |
| EDID manufacturer | `SDC` (Samsung Display Corp) | EDID bytes 8-9: `0x4c83` |
| EDID product code | `0x4217` | EDID bytes 10-11 (LE) |
| DMI sys_vendor | `ASUS` | `/sys/class/dmi/id/sys_vendor` |
| DMI product_name | `ASUS EXPERTBOOK B9406CAA` | `/sys/class/dmi/id/product_name` |
| Touchpad | `093A:4F05` (ACPI `ASCP1D80`) | `/proc/bus/input/devices` |
