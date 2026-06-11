# ASUS ExpertBook Ultra (B9406CAA) — Intel BE211: disable broken EHT, stabilize Wi-Fi 6

The Intel **Wi-Fi 7 BE211** (Panther Lake CNVi, PCI `8086:e440` /
subsystem `8086:0114`) is driven by the new `iwlmld` op_mode. On Linux
6.18 / 7.0 / 7.1-rc the **802.11be (EHT) path on this card is broken**:
EHT RX collapses to **MCS0 / NSS1** and MLO (multi-link) sessions tear
down. The result is that the "Wi-Fi 7" link is in practice *slower and
flakier than plain Wi-Fi 6* — you also see `missed beacons exceeds
threshold` spam and, under heavy traffic, `Microcode SW error` freezes.
This is **not fixed upstream as of Linux 7.1-rc7**.

The working fix is to **turn EHT off and let the card fall back to
802.11ax (Wi-Fi 6 / HE)**, which is rock-solid at full speed (~2.1
Gbit/s at 160 MHz, verified). This is the same approach Omarchy ships
(`/etc/modprobe.d/iwlwifi-disable-eht.conf`, `disable_11be=Y`).

So this is **not** a "keep Wi-Fi 7 alive" module — Wi-Fi 7/EHT genuinely
doesn't work on BE211 yet. It's a "drop the broken EHT layer and make
the Wi-Fi 6 fallback as stable as possible" module.

## Core fix

| Source | Install path | Why |
|---|---|---|
| `iwlwifi-disable-eht.conf` | `/etc/modprobe.d/iwlwifi-disable-eht.conf` | `options iwlwifi disable_11be=Y` — disables 802.11be entirely. The card renegotiates as Wi-Fi 6 / HE (160 MHz, ~2.1 Gbit/s), avoiding the BE211 EHT MCS0/NSS1 collapse and MLO teardown. **This is the fix that actually matters.** Remove it once Intel fixes the iwlwifi EHT path upstream. |

## Secondary tunables

These do **not** keep Wi-Fi 7 alive. They trim the remaining HE-mode
instability (occasional missed-beacon / `Microcode SW error` events) and
are otherwise harmless. Each is independent and additive:

| Source | Install path | Why |
|---|---|---|
| `iwlmld-active.conf` | `/etc/modprobe.d/iwlmld-active.conf` | `options iwlmld power_scheme=1` — disables the driver-side power-save loop that misses beacons. |
| `pcie-aspm-performance.conf` | `/etc/tmpfiles.d/pcie-aspm-performance.conf` | At every boot, write `performance` to `/sys/module/pcie_aspm/parameters/policy`. Disables L0s / L1 / L1.x for the integrated CNVi endpoint. (Per-device ASPM knobs in `/sys/bus/pci/devices/.../link/` don't exist for this hardware — global policy is the only available control.) |
| `90-iwlwifi-no-offload` | `/etc/NetworkManager/dispatcher.d/90-iwlwifi-no-offload` | On every iwlwifi `up` event, run `ethtool -K $iface tso off gso off gro off`. Side-steps the long-standing iwlwifi TX-segmentation-offload bug that triggers `Microcode SW error` and full-system freezes under heavy traffic. |

## What this module deliberately does *not* change

- **Bands below EHT.** 6 GHz and 160 MHz HE (Wi-Fi 6) stay available —
  only the broken 802.11be / 320 MHz EHT layer is dropped. This is a
  deliberate downgrade from Wi-Fi 7 to Wi-Fi 6 because Wi-Fi 7 does not
  work reliably on BE211 yet.
- **Bluetooth coexistence.** `iwlwifi.bt_coex_active=Y` (default). BT
  audio, HID, and file transfer keep working normally.
- **Per-SSID NetworkManager settings.** The card's auto band selection
  is untouched.

## Trade-offs

- **Wi-Fi 7 → Wi-Fi 6**: `disable_11be=Y` gives up 802.11be / 320 MHz
  EHT. On BE211 that band is currently broken (MCS0/NSS1, MLO teardown),
  so you lose nothing usable — the stable Wi-Fi 6 / HE link at 160 MHz
  (~2.1 Gbit/s) is faster in practice than the collapsing EHT link.
  Re-enable EHT (uninstall) once Intel fixes it upstream.
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

You should see all four lines green — the `EHT` line is the one that
matters:

```
EHT:      disable_11be=Y (802.11be off — stable Wi-Fi 6/HE fallback)
iwlmld:   power_scheme=1 (active — no power save)
ASPM:     performance (no L0s/L1/L1.x — best for WiFi)
offload:  tso/gso/gro all off (workaround active on wlan0)
```

Confirm the link came up as HE (Wi-Fi 6), not EHT, and at a high MCS:

```sh
iw dev wlan0 link | grep -iE 'rx bitrate|tx bitrate'
# expect "HE" with a high MCS / NSS 2 — not "EHT MCS 0".
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

- re-enables `802.11be` / EHT (removes `disable_11be=Y`) — only worth
  doing once Intel has fixed the BE211 EHT path upstream
- restores `iwlmld.power_scheme=2`
- restores ASPM policy = default
- re-enables TSO/GSO/GRO on iwlwifi interfaces
- (the ASPM and offload reverts are applied to the running session by the
  uninstall hook so you see them immediately; re-enabling EHT and
  reverting `power_scheme` need a reboot or an `iwlwifi` reload)

## Notes

- This is all userspace tunables. No firmware swap, no kernel patch.
- The RF module on the reference machine is confirmed genuinely BE211
  (`8086:e440`, op_mode `iwlmld`). EHT is broken on the silicon/driver,
  not a misdetection — `disable_11be=Y` is the real fix, the rest is
  polish.
- If `missed beacons` still appears occasionally after the EHT-disable +
  secondary tunables, the remaining cause is signal/SNR — physically
  closer to the AP, or the AP's beacon-interval / DTIM settings, not the
  client driver.
