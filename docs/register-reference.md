# Register reference

Since v1.1.0 the shell scripts **write one register**: Link Control 2. Everything else is
read-only. Offsets are for an Intel PCH root port with the PCI Express capability at `0x40`
(the script prints that check, expecting ID `0x10`).

| Offset | Name | Size | Access in scripts |
|---|---|---|---|
| `0x40` | PCIe Capability ID | 1 | read, expect `0x10` |
| `0x52` | Link Status (`CAP+0x12`) | 2 | read |
| `0x70` | Link Control 2 (`CAP+0x30`) | 2 (low byte) | write `01`-`04` (`gen1`-`gen4`), read back |

## Link Control 2 (`0x70`, low byte)

Bits 3:0 = **Target Link Speed**:

| Value | Speed |
|---|---|
| `0x01` | 2.5 GT/s (Gen1) |
| `0x02` | 5 GT/s (Gen2) |
| `0x03` | 8 GT/s (Gen3); the Cannon Point root port and the RX 580 max out here |
| `0x04` | 16 GT/s (Gen4); invalid unless both ends support it |

It is written **before** the GPU is attached, so the very first link training uses it. It resets
to the port default (`0x03` here) on any root-port reset, including S3 resume. That's why a GPU
that appears after sleep/wake runs at Gen3.

## Link Status (`0x52`)

| Bits | Meaning |
|---|---|
| 3:0 | Current speed: 1 = 2.5 GT/s, 2 = 5 GT/s, 3 = 8 GT/s |
| 9:4 | Negotiated width |
| 11 | Link Training in progress |
| 12 | Slot Clock Configuration |
| 13 | **Data Link Layer Link Active**: the link is usable |
| 14/15 | Bandwidth management / autonomous bandwidth status |

Observed values:

| Value | Meaning |
|---|---|
| `0x5011` | Gen1 x1, not active. The PHY sees the GPU but the link didn't come up. |
| `0x5811` | Stuck in training, not active. |
| `0x7011` | Gen1 x1, **active** |
| `0x7012` | Gen2 x1, **active** |

## Registers used in v1.0.0, no longer written

v1.0.0 also pulsed a **Secondary Bus Reset** (Bridge Control `0x3E` bit 6) and did a Link Control
(`0x50`) disable → enable → retrain sequence with ASPM off. In 18 logged runs, this never turned a
failed link into a working one, and once broke a working link, so it was removed. See
[how-it-works.md §5](how-it-works.md#5-gpu-attached-in-the-shell-link-sometimes-never-comes-up).

## UEFI Shell `mm` addressing

`mm ssssbbddffrr -pci -w <bytes> [value] -n`, for example `mm 0000001D0070 -pci -w 1 -n` reads
segment 0, bus `00`, device `1D`, function `00`, register `0x70`.
