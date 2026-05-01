# intel-perf-fix

Brings the same Intel Panther Lake / Lunar Lake userspace power & thermal
tuning that **Omarchy 3.5 / 3.6** enables out of the box, ported to
KDE Plasma + Arch / CachyOS.

## What gets installed

| Package | From | Service | What it does |
|---|---|---|---|
| `thermald` | `extra` repo | `thermald.service` | Intel thermal-management daemon. P/E-core-aware throttle that's significantly smarter than the kernel's default on Panther Lake's hybrid topology. |
| `intel-lpmd` | AUR (via paru/yay) | `intel_lpmd.service` | Intel Low Power Mode Daemon. When the system is idle, parks all workload on a single LP-E core and lets the P-cores deep-sleep. Single biggest idle-power win on PTL — Omarchy reports 2 W idle on Framework 13, 2.2 W on XPS 16 OLED with this enabled. |

Both daemons coexist with `power-profiles-daemon` (which we already had).
`thermald` handles thermal throttle; PPD handles user power profile;
`intel-lpmd` handles idle core selection. Three different layers, no conflict.

## What we deliberately don't include

Omarchy 3.5 / 3.6 also bundles:

- **Hyprland-specific toggles** (window-gap persistence, touchpad on/off via
  `XF86TouchpadOn`, scaling cycle, etc.) — not relevant on KDE Plasma.
- **Dell-DMI-gated kernel patches** (Panel Replay, CS42L43 SOF, Wi-Fi 7 BE2xx
  Dell-XPS quirk, haptic-trackpad Synaptics quirk) — proven not to apply to
  this ASUS B9406CAA. The upstream `intel_quirks.c` entry matches PCI
  subsystem `0x1028:0x0db9` (Dell XPS 14 DA14260); ours is `0x1043:0x15e4`.
  Our `display-fix` module handles the same problem with a cmdline param
  scoped to our hardware.
- **ThinkPad mic-mute LED sync** — different vendor.
- **T2 Mac / Tuxedo / Slimbook keyboard fixes** — different hardware.
- **`/home` btrfs snapshot churn fix** — we don't snapshot `/home` (no
  `snapper -c home` config on this system).

## Install

```sh
./patch.sh install intel-perf-fix
```

After install (no reboot needed), verify:

```sh
./patch.sh status intel-perf-fix
# expect:
#   thermald.service       active
#   intel_lpmd.service     active
#   thermald pkg:          2:2.5.x-...
#   intel-lpmd pkg:        0.1.0-...
```

Quick sanity: drop CPU to idle for ~30 s, then run `powertop` or
`turbostat`. You should see most of the system idle on a single LP-E core
(`CPU 0` / `CPU 1` instead of all 12 wandering).

## Uninstall

```sh
./patch.sh uninstall intel-perf-fix
```

Disables both services. Packages are left installed so reverting is
reversible without re-fetching from the network. To remove them fully:

```sh
sudo pacman -Rns thermald
paru   -Rns intel-lpmd
```

## Note: the AUR step

`intel-lpmd` lives only in the AUR. The module's install hook re-invokes
`paru` (or `yay`, whichever is on `$PATH`) **as the original `$SUDO_USER`**,
because both helpers refuse to run under root. If your environment has
neither helper, install manually:

```sh
paru -S intel-lpmd
sudo systemctl enable --now intel_lpmd.service
```
