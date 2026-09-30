# Cleanup: reverting every change

| Change | How to revert |
|---|---|
| Boot entries from `Set-BootConfig.ps1` | `.\scripts\Remove-BootConfig.ps1` (deletes exactly the recorded IDs; the BCD export stays in `%ProgramData%\latitude-5400-egpu\`) |
| Files on the USB stick | Delete `\EFI\shell\` on the stick. Nothing else was touched. |
| Secure Boot off | BIOS → Secure Boot → Secure Boot Enable. |
| Root-port register writes | Nothing to do; they reset on power-off. |
| CLKREQ# mod | Hardware; leave it or undo the bridge. |

## Only if you followed the DSDT experiments

| Change | How to revert |
|---|---|
| Registry DSDT override | Delete `HKLM\SYSTEM\CurrentControlSet\Services\ACPI\Parameters\DSDT` |
| Testsigning | `bcdedit /set {id} testsigning off` for each entry you set it on |
| Crash display settings | `CrashControl\DisplayParameters` → delete, `AutoReboot` → `1` |
| Tools | `choco uninstall iasl`; the Windows Driver Kit from *Apps & features* |
