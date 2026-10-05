# Hardware

## Parts

| Part | Notes |
|---|---|
| Dell Latitude 5400 | Intel 8th-gen U-series, Cannon Point-LP PCH. Uses **S3** sleep, not Modern Standby (`powercfg /a`). |
| M.2 slot on Root Port `00:1D.0` | PCIe x1 as wired to this slot. Windows calls it "Intel PCI Express Root Port #12 - 9DB3"; in ACPI it is `\_SB.PCI0.RP13`. |
| M.2 adapter / key adapter | Converts the slot to an M.2 M-key, then to the riser. |
| USB-cable PCIe x1 riser | The "mining riser" style: an x1 card + USB 3 cable + x16 slot board. |
| Sapphire RX 580 | `1002:67DF`. BAR0 is 256 MB (8 GB preferred with Resizable BAR), plus 2 MB, 256 KB and 256 B of I/O. |
| External ATX PSU | Powers the GPU and the riser board. |
| Placeholder NVMe SSD | Any M.2 NVMe that fits the slot. It is only there during POST so the BIOS keeps the root port enabled. |
| USB stick (FAT32) | Holds the UEFI Shell. Existing content (e.g. a Linux installer) can stay. |

## Required mod: CLKREQ# to GND

Without it, the GPU never powered up its link (no fans, nothing detected). The slot only drives
the 100 MHz reference clock when the endpoint asserts **CLKREQ#** (active low). Riser/adapter
chains often leave it floating.

- Tie **CLKREQ#** to **GND** on the M-key side of the adapter chain (M.2 key M: pin 52 =
  CLKREQ#; nearby GND pins are 51, 57, 71, 73, 75; pin 69 is PEDET, **not** GND). Check your
  adapter's pinout with a meter before soldering.
- After the mod, the reference clock runs continuously and the GPU fans spin at power-on.

## Power and connection order (important)

The order that works:

1. Laptop is in the UEFI Shell with the link speed already chosen (`gen1`-`gen4`).
2. Remove the placeholder SSD.
3. Plug in the eGPU adapter **with the GPU PSU OFF**.
4. Switch the PSU **ON**, wait ~5 s.
5. Press a key; the script checks whether the GPU answers.
6. If it reads `FF FF`: **PSU off 5 s, on 5 s**, type `again`. Repeat until it answers.

Why: the GPU has to come out of its power-on reset while the reference clock is already
running. Otherwise it never sees a PERST# pulse, and the link gets stuck in training (Link Status
`Link Training = 1`, `DLL Link Active = 0`). Powering the GPU **after** the clock is present lets
its power-on reset do the job PERST# normally does. This doesn't succeed every time; a second PSU
power-cycle has always fixed it so far. Software resets (Secondary Bus Reset, link
disable/retrain) **never** rescued a failed attempt. See
[how-it-works.md](how-it-works.md#5-gpu-attached-in-the-shell-link-sometimes-never-comes-up).

> Hot-swapping M.2 devices while the laptop is powered on stresses the connector and the devices.
> Insert straight and quickly, and don't rock the card. You accept that risk.

## Optional: PERST# switch

If the power-order trick is not enough on your riser, the robust fix is a switch that holds
**PERST#** (M.2 key M pin 50) low while you swap, and releases it once the GPU is powered.
Commercial adapters (e.g. EXP GDC) have a "PERST delay" setting for the same reason.
This was **not needed** in the tested setup.
