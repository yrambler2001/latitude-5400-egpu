# DSDT notes: why an override is not needed here

The classic egpu.io advice for Code 12 on laptops is a DSDT override that adds a large 36-bit
memory window to the PCI host bridge. **It doesn't apply to the Latitude 5400:**

| Question | Answer on this machine |
|---|---|
| Is there room for a 256 MB BAR below 4 GB? | Yes. PCI0 window `0x7D800000-0xEFFFFFFF`, ~1.5 GB free, all 256 MB-aligned blocks from `0x90000000` free. |
| Does Windows allocate it once the GPU is present **at boot**? | Yes: `0xD0000000-0xDFFFFFFF`. |
| Did a 36-bit window at `0xC20000000-0xE0FFFFFFF` work? | No. BSOD 0x124 (machine check) at boot, even with the GPU disconnected. |

Check your own machine before doing any DSDT work (read-only, elevated PowerShell):

```powershell
$pci0 = Get-CimInstance Win32_PnPEntity | ? DeviceID -like 'ACPI\PNP0A08*' | select -First 1
Get-CimAssociatedInstance -InputObject $pci0 -ResultClassName Win32_DeviceMemoryAddress |
  % { '{0:X} - {1:X}' -f [uint64]$_.StartingAddress, [uint64]$_.EndingAddress } | sort -Unique
```

## If you do need an override: lessons learned

1. **Test the round-trip first.** Decompile the unmodified table, recompile it with `iasl -oa` and
   compare the bytes. On this Dell DSDT the result was 556 bytes smaller and different from the
   first opcode, and loading it caused a machine check.
2. **Prefer binary patching** of the original AML when the change is small. Find unique byte
   patterns, patch in place, keep the size, and recompute the checksum (byte 9, table sums to 0).
   Then disassemble the original and the patched table **the same way** and diff them; only your
   change should show.
3. **Verify what `asl /loadtable` wrote.** Reassemble the registry chunks and compare hashes.
4. **Keep an escape hatch.** Add a boot entry **without** testsigning. Windows ignores the registry
   override on that entry, so a bad table is one menu choice away from a working boot.
5. **Run a control test.** Load the *unmodified* table as an override. If that boots and your
   patched one doesn't, the patch content is the problem, not the mechanism.
6. **Don't publish dumps.** OEM ACPI tables are proprietary firmware. This repo doesn't include
   any.
