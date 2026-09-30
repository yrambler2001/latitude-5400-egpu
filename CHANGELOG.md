# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
