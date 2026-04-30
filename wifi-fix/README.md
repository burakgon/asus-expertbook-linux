# ASUS ExpertBook Ultra (B9406CAA) — Wi-Fi 7 stability fixes

The Intel **Wi-Fi 7 BE211** (Panther Lake CNVi, PCI `8086:e440` /
subsystem `8086:0114`) is driven by the new `iwlmld` op_mode. Out of
the box on Linux 6.18+ / 7.x the link is unstable on Wi-Fi 7 / 6 GHz /
320 MHz: kernel logs spam `missed beacons exceeds threshold, but
receiving data`, throughput craters, and on heavy traffic you can hit
full 10-second freezes from `Microcode SW error`.

This module bundles three independent userspace fixes — none of them
downgrade the link, none of them touch Bluetooth.

| Source | Install path | Why |
|---|---|---|
| `iwlmld-active.conf` | `/etc/modprobe.d/iwlmld-active.conf` | `options iwlmld power_scheme=1` — disables the driver-side power-save loop that misses beacons. |
| `pcie-aspm-performance.conf` | `/etc/tmpfiles.d/pcie-aspm-performance.conf` | At every boot, write `performance` to `/sys/module/pcie_aspm/parameters/policy`. Disables L0s / L1 / L1.x for the integrated CNVi endpoint. (Per-device ASPM knobs in `/sys/bus/pci/devices/.../link/` don't exist for this hardware — global policy is the only available control.) |
| `90-iwlwifi-no-offload` | `/etc/NetworkManager/dispatcher.d/90-iwlwifi-no-offload` | On every iwlwifi `up` event, run `ethtool -K $iface tso off gso off gro off`. Side-steps the long-standing iwlwifi TX-segmentation-offload bug that triggers `Microcode SW error` and full-system freezes under heavy traffic. |

## What this module deliberately does *not* change

- **Wi-Fi band, channel width, or protocol.** Wi-Fi 7 / 6 GHz / 320 MHz
  stays the card's preferred mode.
- **Bluetooth coexistence.** `iwlwifi.bt_coex_active=Y` (default). BT
  audio, HID, and file transfer keep working normally.
- **Per-SSID NetworkManager settings.** The card's auto band selection
  is untouched.

## Trade-offs

- **Idle power**: ASPM=performance disables L1.x on every PCIe device,
  so idle power draw climbs by ~1-3 W on this laptop. Acceptable for a
  laptop on AC; on long battery sessions you may want to uninstall.
- **CPU at line-rate**: TSO/GSO/GRO off pushes segmentation back to the
  CPU. On Core Ultra silicon this is negligible (a few % of one core)
  compared to the cost of the segmentation-offload bug.

## Install

```sh
./patch.sh install wifi-fix
sudo reboot
```

After reboot, verify:

```sh
./patch.sh status wifi-fix
```

You should see all three lines green:

```
iwlmld:   power_scheme=1 (active — no power save)
ASPM:     performance (no L0s/L1/L1.x — best for WiFi)
offload:  tso/gso/gro all off (workaround active on wlan0)
```

And the kernel-log spam should stop:

```sh
sudo dmesg | grep -c "missed beacons"
sudo dmesg | grep -c "Microcode SW error"
# both should be zero on a stable session
```

## Uninstall

```sh
./patch.sh uninstall wifi-fix
sudo reboot
```

Removing the module:

- restores `iwlmld.power_scheme=2`
- restores ASPM policy = default
- re-enables TSO/GSO/GRO on iwlwifi interfaces
- (the install/uninstall hooks also apply those reverts to the running
  session so you can see the effect immediately)

## Notes

- This is all userspace tunables. No firmware swap, no kernel patch.
- If `missed beacons` still appears occasionally after all three fixes,
  the remaining cause is signal/SNR — physically closer to the AP, or
  the AP's beacon-interval / DTIM settings, not the client driver.
