# Troubleshooting

Start with `.\scripts\Get-EgpuStatus.ps1`. It summarises:
- the root port and the devices behind it;
- the WHEA counts;
- the boot entry;
- the last shell run (chosen speed, Link Status, endpoint).

| Symptom | Check | Likely cause → fix |
|---|---|---|
| Root port not found / `present=False` | `Get-EgpuStatus.ps1` | Slot was empty at POST, so the BIOS disabled the port. Put the placeholder SSD in before power-on. |
| BSOD `0xA5` at boot | Was the GPU powered at POST? | Don't power or plug the GPU until the shell asks. To read parameters: `CrashControl\DisplayParameters=1`. |
| F12 doesn't list the USB stick | Stick plugged in? FAT32? | Use a FAT32 stick. In BIOS make sure USB boot is enabled. |
| Picking the stick boots something else | `\EFI\BOOT\BOOTX64.EFI` on the stick | Another bootloader is there. Re-run `Install-UsbShell.ps1 -ReplaceBootloader`. |
| Shell opens but the script doesn't start | — | Type `fs0:` (or the fsN holding `\EFI\shell`), then `cd \EFI\shell`, then `startup.nsh`. |
| `gen2` → "not found" | — | Type `gen2.nsh`. Make sure you're in `\EFI\shell`. |
| Capability check isn't `0x10` | `pci 00 1D 00 -i` | Different root port or chipset. Find the PCIe capability offset and use `-PcieCapOffset`. Don't continue with wrong offsets. |
| GPU check shows `FF FF ...`, Link Status `0x5…` | — | Press `q`, PSU **off 5 s / on 5 s**, type `again`. Repeat. Reseat the adapter. Check the CLKREQ# mod. If it never comes up, consider a PERST# switch ([hardware.md](hardware.md)). |
| GPU visible in shell, **Code 12** in Windows | Which boot entry? | Pick **Windows 11 (eGPU)** (`usefirmwarepcisettings No`). Don't sleep. |
| Code 12 after waking from sleep, link at Gen3 | — | S3 resume restores the BIOS's 1 MB window and default speed. Reboot through the shell. |
| Many WHEA event 17 | `Get-EgpuStatus.ps1` | Link too fast for the riser. Choose one speed lower next boot. Shorter or better cable. |
| Code 43 on the GPU's HDMI audio function | — | Side effect of the GPU not starting. Fix the GPU first. |
| Windows won't boot after DSDT experiments | — | Pick a boot entry without testsigning, or delete `HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters\DSDT` from WinRE regedit (load the offline SYSTEM hive). |
