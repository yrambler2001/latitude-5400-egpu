# Troubleshooting

Start with `.\scripts\Get-EgpuStatus.ps1`. It summarises the root port, the devices behind it, the
WHEA counts, the boot entry and the last shell run.

| Symptom | Check | Likely cause → fix |
|---|---|---|
| Root port not found / `present=False` | `Get-EgpuStatus.ps1` | Slot was empty at POST, so the BIOS disabled the port. Put the placeholder SSD in before power-on. |
| BSOD `0xA5` at boot | Was the GPU powered at POST? | Don't power or plug the GPU until the shell asks. To read parameters: `CrashControl\DisplayParameters=1`. |
| F12 has no "UEFI Shell (eGPU)" | Stick plugged in? `bcdedit /enum firmware` | Some firmware drops entries for absent devices. Re-run `Set-BootConfig.ps1` (after `Remove-BootConfig.ps1`), or boot the stick's GRUB and `chainloader /EFI/shell/shellx64.efi`. |
| Shell opens but the script doesn't start | — | Type `fs0:` (or the fsN holding `\EFI\shell`), then `cd \EFI\shell`, then `startup.nsh`. |
| Capability check isn't `0x10` | `pci 00 1D 00 -i` | Different root port or chipset. Find the PCIe capability offset and use `-PcieCapOffset`. Don't continue with wrong offsets. |
| GPU check shows `FF FF ...` | Log: Link Status | `0x5x11` with bit 13 = 0 means the link isn't up. Power-cycle the GPU PSU **after** it's plugged in, then rerun `startup.nsh`. Reseat the adapter. Check the CLKREQ# mod. If it persists, consider a PERST# switch ([hardware.md](hardware.md)). |
| GPU visible in shell, **Code 12** in Windows | Which boot entry? | Pick **Windows 11 (eGPU)** (`usefirmwarepcisettings No`). Don't sleep. |
| Code 12 after waking from sleep | — | S3 resume restores the BIOS's 1 MB window. Reboot through the shell. |
| Many WHEA event 17 | `Get-EgpuStatus.ps1` | Link at Gen2/3 on a marginal riser. Keep Gen1 (the default). Shorter or better cable. |
| Code 43 on the GPU's HDMI audio function | — | Side effect of the GPU not starting. Fix the GPU first. |
| Windows won't boot after DSDT experiments | — | Pick a boot entry without testsigning, or delete `HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters\DSDT` from WinRE regedit (load the offline SYSTEM hive). |
