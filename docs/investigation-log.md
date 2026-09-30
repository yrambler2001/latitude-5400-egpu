# Investigation log

This is the chronological record, including the dead ends. It shows what was tried, what it
showed, and why the next step followed. Times are from one session.

## Starting point

- **CLKREQ# grounded.** Before this the GPU didn't power its link. After it, the fans spin.
- **GPU powered at POST:** BSOD `0xA5 ACPI_BIOS_ERROR`.
- **Sleep, power the GPU on, wake:** BSOD `0xEF CRITICAL_PROCESS_DIED`. This was an older attempt,
  not reproduced later.
- **Hot-plug after boot + Scan for hardware changes:** not detected.
- A GT 610 had been detected intermittently in the same slot.

## 1. Safety baseline

- BitLocker off, Secure Boot on (later turned off), 20 GB RAM.
- Created a System Restore point.
- Fast Startup was on. A "Shut down" is then really a hibernate, so boot-menu tricks need **Restart**.

## 2. Power the GPU at the Boot Manager menu → not detected

The root port `00:1D.0` itself was `Present: False`, so the BIOS had disabled it at POST.
→ [how-it-works §1](how-it-works.md#1-the-bios-switches-off-an-empty-slots-root-port)

## 3. DSDT override attempts (dead end, 2× BSOD 0x124)

The plan was nando4's standard fix: add a 36-bit `QWordMemory` window to the PCI0 `_CRS`.

| Attempt | Result | Lesson |
|---|---|---|
| Decompile with `iasl -d`, edit, recompile, load with `asl /loadtable` | **BSOD 0x124** in normal *and* Safe Mode | The Dell DSDT does **not** round-trip: recompiling the *unmodified* table gives 556 fewer bytes, differing from the first opcode. Never trust a recompile without a byte-for-byte round-trip test. |
| **Binary patch** of the original AML (11 bytes: fill the existing 64-bit descriptor with `0xC20000000-0xE0FFFFFFF`, repoint the code that zeroed its length, fix the checksum) | **BSOD 0x124** again | This table was faithful, so the problem was the window itself (see the control test). |
| **Control test:** load the *unmodified* original as an override | **Boots fine** | The override mechanism works; the 36-bit window at `0xC20000000` is what crashed this machine. |

To make these experiments safe, a second boot entry **without** testsigning was created. Windows
ignores registry DSDT overrides unless testsigning is on, so a bad table can be skipped from the
boot menu with no recovery needed.

Then the memory map showed the PCI0 32-bit window has **~1.5 GB free**, so no extra window was
needed at all. → [dsdt-notes.md](dsdt-notes.md)

## 4. Getting the 0xA5 parameters

`CrashControl\DisplayParameters=1`, `AutoReboot=0` → `0xA5 (0x1000, 0x1, 0x5417, 0x4)`:
Dell AML tried to map RAM at `0x1_0000_5417`.
→ [how-it-works §2](how-it-works.md#2-gpu-present-at-post--bsod-0xa5)

## 5. The placeholder-SSD trick (found by the user)

**SSD in the slot at POST** keeps the port alive. Then swap to the eGPU at the boot menu and do
**S3 sleep → wake**. The RX 580 appears, but with **Code 12**.

- The requirement list was decoded: 8 GB preferred / 256 MB aligned fallback, 2 MB, 256 KB, 256 B I/O.
- The root-port window was 1 MB, while 256 MB-aligned blocks were free.
- Runtime fixes all failed: restart-device, `usefirmwarepcisettings no`, remove + rescan.
- Thousands of WHEA-17 events at Gen3.

→ [how-it-works §3-4](how-it-works.md#3-after-s3-sleepwake-code-12-with-a-1-mb-window)

## 6. UEFI Shell, run 1: link stuck in training

The shell set Gen1, then did link disable/enable + retrain after a **hot swap with the GPU
already powered**. Link Status stayed `0x5811` (training stuck, DLL inactive) and the endpoint
read `FF`.

- There's no ACPI-controlled PERST# GPIO for this slot. The only reset in `RP13.PXSX` is a Function
  Level Reset, which needs a working link.
- The machine uses S3, whose platform reset is what re-initialised the GPU on wake.

## 7. UEFI Shell, run 2: working

The adapter was plugged in with the **GPU PSU off**, then the PSU switched on; the script added a
Secondary Bus Reset.

- Link Status `0x7011` (Gen1 x1, DLL active), endpoint `1002:67DF`.
- Windows booted, enumerated the GPU and allocated `0xD0000000-0xDFFFFFFF`.
- The RX 580 is **OK, code 0**, AMD driver 31.0.12027.9001, **0 WHEA** events.

## Tooling notes

- `acpidump -b` on Windows can't read dynamically loaded SSDTs ("Could not get SSDT registry entry").
- `iasl -e` with several SSDTs failed with `AE_ALREADY_EXISTS`. Standalone disassembly works but
  can't be recompiled faithfully.
- `asl.exe /loadtable` (from the WDK) stores the table as chunks under
  `HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters\DSDT\<OEM>\<Table>\<Rev>`:
  - the first value has a 16-byte header (total length at +0, chunk length at +12);
  - later values have an 8-byte header (offset, length).

  Reassemble and hash-compare before rebooting.
- In Windows PowerShell 5.1, hex literals above `0x7FFFFFFF` are **negative Int32**. Use
  `[uint64]` for address math.
