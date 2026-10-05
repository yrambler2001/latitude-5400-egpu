# Cleanup: reverting every change

| Change | How to revert |
|---|---|
| Windows boot entry from `Set-BootConfig.ps1` | `.\scripts\Remove-BootConfig.ps1` (deletes exactly the recorded ID; the BCD export stays in `%ProgramData%\latitude-5400-egpu\`) |
| USB stick | Delete `\EFI\shell\`, `\EFI\BOOT\startup.nsh` and `\startup.nsh`. Delete `\EFI\BOOT\BOOTX64.EFI`, or rename `BOOTX64.EFI.orig` back if the installer kept a previous bootloader. Or just reformat the stick. |
| Secure Boot off | BIOS → Secure Boot → Secure Boot Enable. |
| Link speed setting | Nothing to do; it resets on power-off. |
| CLKREQ# mod | Hardware; leave it or undo the bridge. |

## Only if you used v1.0.0

v1.0.0 also created a firmware (F12) boot entry "UEFI Shell (eGPU)". `Remove-BootConfig.ps1`
deletes it too if it is recorded in the state file. Otherwise find it with `bcdedit /enum firmware`
and `bcdedit /delete {id}`.

## Only if you followed the DSDT experiments

| Change | How to revert |
|---|---|
| Registry DSDT override | Delete `HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters\DSDT` |
| Testsigning | `bcdedit /set {id} testsigning off` for each entry you set it on |
| Crash display settings | `CrashControl\DisplayParameters` → delete, `AutoReboot` → `1` |
| Tools | `choco uninstall iasl`; the Windows Driver Kit from *Apps & features* |
