# How it works: the root-cause chain

Each obstacle below was observed directly, and the evidence is listed. Where something is
inferred rather than proven, it says so.

## 1. The BIOS switches off an empty slot's root port

**Observation:** with nothing in the slot at POST, Root Port `00:1D.0` (`8086:9DB3`) shows as
`Present: False` in Windows. Hot-plugging the GPU later, and "Scan for hardware changes", find
nothing. The GPU powering up at the Windows Boot Manager menu also finds nothing.

**Why:** Intel reference BIOS code function-disables root ports with no link at POST, to save power.
Once disabled, the port disappears from PCI configuration space until the next reset.

**Consequence:** something must be in the slot at POST. Powering the GPU at POST gives the next
problem, so the method uses a **placeholder NVMe SSD** instead.

## 2. GPU present at POST → BSOD 0xA5

**Observation:** with the GPU powered at POST, Windows stops with `ACPI_BIOS_ERROR (0xA5)`:

| P1 | P2 | P3 | P4 |
|---|---|---|---|
| `0x1000` | `0x1` | `0x5417` | `0x4` |

Per Microsoft's reference, P1 `0x1000` = *"ACPI had a fatal error when processing a memory
operation region"*. P2:P3 is the physical address, P4 the length. So Dell's AML tried to map
**`0x1_0000_5417`** (4 bytes). That is ordinary RAM just above 4 GB, and Windows refuses AML
access to RAM.

**Inference (not proven):** the BIOS fails to fit the GPU's 256 MB BAR behind this root port and
leaves some state half-set-up. An ACPI method then computes an address from a register that
reads back garbage (the value is consistent with `0xFFFFFFFF + 0x5418`). The exact method was not
identified. `0x5418` does not appear as a constant in the static DSDT/SSDTs, and 4 SSDTs are
loaded dynamically and could not be dumped from Windows. A kernel debugger (`!amli lc`) would
name it.

To get the parameters at all, you need `HKLM\SYSTEM\CurrentControlSet\Control\CrashControl`
`DisplayParameters=1`. The crash happens too early for a dump or event log entry.

## 3. After S3 sleep/wake: Code 12 with a 1 MB window

**Observation:** boot with the SSD in the slot, swap to the eGPU at the boot menu, then S3
sleep → wake: the RX 580 enumerates (Gen3 x1), but with **Code 12** (not enough resources).

- The root port's memory window is **1 MB** (`0x7F200000-0x7F2FFFFF`), sized by the BIOS for the SSD.
- The GPU asks for 8 GB (Resizable BAR), or 256 MB **aligned to 256 MB**, plus 2 MB, 256 KB and 256 B I/O.
  These were decoded from `HKLM\SYSTEM\CurrentControlSet\Enum\PCI\...\LogConf\BasicConfigVector`.
- The PCI host bridge's 32-bit window `0x7D800000-0xEFFFFFFF` has about **1.5 GB free**. Every
  256 MB-aligned block from `0x90000000` to `0xE0000000` is unused.

**So a DSDT "36-bit window" override is not needed on this laptop.** The space exists. Windows
just won't **grow** a non-hot-plug root port's window at runtime. None of these helped:

- `pnputil /restart-device` on the root port
- `bcdedit /set usefirmwarepcisettings no` + reboot (the GPU still only appeared after wake)
- `pnputil /remove-device /subtree` on the root port + `pnputil /scan-devices`

**Why wake works at all:** S3 resume pulses the platform reset, which drives the slot's
**PERST#**. The GPU gets a clean reset with power and clock stable, and the link trains. On
resume the BIOS also restores the saved root-port configuration, including the 1 MB window.

## 4. Link errors at Gen3

**Observation:** while the GPU was up at Gen3 (8 GT/s), Windows logged **~12,000 WHEA-Logger
event 17** (corrected PCIe AER errors) in two minutes. All came from Root Port `00:1D.0`.

**Conclusion:** the M.2-adapter + USB-cable riser chain can't carry Gen3 cleanly. At **Gen1** the
count is **0**.

## 5. GPU attached in the shell: link sometimes never comes up

**Observation** (UEFI Shell log): with the GPU already powered, then plugged in after
removing the SSD:

- Link Status `0x5011`, then `0x5811` after retrain attempts:
  - `Link Training` = 1 (stuck), `Data Link Layer Link Active` = 0
- The endpoint config space reads all `FF`.

The PHY detects a receiver, but the link never reaches L0.

**What works:** plug the adapter with the **GPU PSU off**, then switch it on, so the GPU comes out
of its power-on reset with the reference clock already running. That doesn't succeed every time.
When it fails, **power-cycling the PSU again and re-checking** has always brought the link up.

**Evidence from 18 logged shell runs:**

| Finding | Runs |
|---|---|
| In every successful run, the GPU already answered right after the swap, before any software reset | 7 of 7 |
| A failed swap (`FF FF`) was rescued by Secondary Bus Reset / link disable / retrain | 0 |
| A working link was **broken** by the reset/retrain sequence | 1 |
| Failed runs fixed by a PSU power-cycle + re-check | every case tried |

So since v1.1.0 the scripts do **no** software reset at all. They set the target speed, wait for
the swap, check, and let you retry with a PSU power-cycle (`again`).

**Speed:** Gen1 and Gen2 both come up. With Gen2 the link was `0x7012` (5 GT/s x1, active).
The initial link-up difficulty was the same at both speeds.

## 6. Enumerated at boot → Windows allocates it

With the link up **before** Windows starts, Windows enumerates the GPU during boot and places it
in a new 256 MB window, `0xD0000000-0xDFFFFFFF`. The result:
- code 0, AMD driver loaded;
- 0 AER errors at Gen1;
- 12 AER errors at idle at Gen2 (sustained load not yet measured).

The boot entry used had `usefirmwarepcisettings No`. **Not isolated:** it has not been tested
whether a normal entry also allocates correctly when the GPU is present at boot.

## Summary

```
empty slot at POST ──► root port disabled ─────────────► never detectable
GPU at POST ─────────► BIOS allocation fails ──────────► 0xA5 in Dell AML
SSD at POST, swap ───► port alive, GPU needs a clean power-on
                         ├─► S3 wake: works, but Code 12 (1 MB window)
                         └─► UEFI Shell: set speed, PSU on after plug (retry PSU cycle if FF)
                               ──► GPU visible at boot ──► Windows sizes window ──► OK
```