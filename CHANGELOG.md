# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-05

### Changed
- **The USB stick boots the shell directly.** `Install-UsbShell.ps1` installs it as
  `\EFI\BOOT\BOOTX64.EFI` plus a launcher `startup.nsh`. Picking the stick in F12 is enough.
  It refuses to overwrite another bootloader without `-ReplaceBootloader`, and keeps it as `.orig`.
- `Set-BootConfig.ps1` only creates the Windows entry (`usefirmwarepcisettings No`). The F12
  firmware entry is gone, and so is the `-UsbDriveLetter` parameter.
- **Shell flow:**
  1. `startup.nsh` checks the port and shows a speed menu.
  2. You type `gen1`-`gen4`, which runs `flow.nsh <speed>`: it sets Link Control 2 and guides the swap.
  3. `again.nsh` checks the GPU. On `FF FF` you power-cycle the PSU and type `again`.
- `Get-EgpuStatus.ps1` shows the chosen target speed from the log.

### Removed
- Secondary Bus Reset and link disable/retrain from the shell scripts. In 18 logged runs they never
  rescued a failed link and once broke a working one. The `-BridgeControl` parameter is removed.

### Documentation
- Gen2 x1 confirmed working (12 WHEA events at idle).
- Procedure, hardware power order, how-it-works §5/§6, register reference, troubleshooting,
  adapting, cleanup and the investigation log are updated.
## [1.0.0] - 2026-09-30

### Added
- UEFI Shell bring-up script (`startup.nsh`):
  - Gen1 link limit;
  - guided swap with power-after-plug;
  - Secondary Bus Reset, link disable/enable and retrain;
  - full logging to the USB stick.
- `win.nsh` to chainload Windows Boot Manager.
- `Install-UsbShell.ps1`: downloads the EDK2 UEFI Shell (pbatard 26H1), verifies its SHA256 and
  renders the templates for any root port.
- `Set-BootConfig.ps1` / `Remove-BootConfig.ps1`: create and remove the Windows
  (`usefirmwarepcisettings No`) and F12 shell entries, with a BCD export and a state file.
- `Get-EgpuStatus.ps1`: read-only report (devices, windows, link, WHEA, boot config, decoded shell log).
- Documentation:
  - root-cause chain;
  - procedure;
  - investigation log with dead ends;
  - DSDT lessons;
  - register reference;
  - troubleshooting;
  - adapting;
  - cleanup.
