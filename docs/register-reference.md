# Register reference

These are all the registers `startup.nsh` reads or writes. Offsets are for an Intel PCH root port
with the PCI Express capability at `0x40` (the script checks for ID `0x10` there before doing
anything).

| Offset | Name | Size | Access in script |
|---|---|---|---|
| `0x3E` | Bridge Control | 2 (script uses low byte) | read; write `orig \| 0x40` then `orig` |
| `0x40` | PCIe Capability ID | 1 | read, expect `0x10` |
| `0x50` | Link Control (`CAP+0x10`) | 2 (low byte) | write `0x50` → `0x40` → `0x60` |
| `0x52` | Link Status (`CAP+0x12`) | 2 | read |
| `0x70` | Link Control 2 (`CAP+0x30`) | 2 (low byte) | write `0x01` |

## Bridge Control (`0x3E`)

| Bit | Meaning |
|---|---|
| 6 | **Secondary Bus Reset**: while set, a hot reset is signalled downstream |
| 4 | VGA 16-bit decode (was `1` on the tested machine, so the original value is `0x10`) |
| 1 | SERR# enable |

The script writes `orig | 0x40`, waits 100 ms, then restores `orig`.

## Link Control (`0x50`, low byte)

| Bit | Meaning | Value written |
|---|---|---|
| 1:0 | ASPM control | `00` = off (was `10` = L1) |
| 4 | Link Disable | pulsed |
| 5 | Retrain Link | set once |
| 6 | Common Clock Configuration | `1` |

The sequence is `0x50` (disable) → wait 200 ms → `0x40` (enable) → wait 1 s → `0x60` (retrain) → wait 3 s.
The original value was `0x42`. The script leaves `0x40`, which turns ASPM off. That is intended,
because ASPM on flaky eGPU links causes drops.

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
| `0x7011` | Gen1 x1, **active**. Working. |

## Link Control 2 (`0x70`, low byte)

Bits 3:0 = Target Link Speed. `0x01` = 2.5 GT/s (Gen1), `0x02` = Gen2, `0x03` = Gen3.
Writing `0x01` limits the next training to Gen1. It resets on the next power cycle.

## UEFI Shell `mm` addressing

`mm ssssbbddffrr -pci -w <bytes> [value] -n`, for example `mm 0000001D0050 -pci -w 1 -n` reads
segment 0, bus `00`, device `1D`, function `00`, register `0x50`.
