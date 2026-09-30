# Contributing

Reports from other machines are the most useful contribution.

## Reporting a result (works or not)

Open an issue with:
- Laptop model, BIOS version, CPU/PCH, sleep type (`powercfg /a`).
- Slot and root port (`Get-EgpuStatus.ps1` output).
- Adapter/riser chain and GPU.
- The last run from `\EFI\shell\egpu-log.txt`. The sections `[1]`, `[2]`, `[3]` with the Link
  Status values are enough.
- **Remove** serial numbers, MAC addresses and user names before posting.

## Pull requests

- Keep scripts compatible with **Windows PowerShell 5.1** and the **EDK2 UEFI Shell 2.2**.
- Scripts that change the system must support `-WhatIf` and must be reversible.
- **Don't commit firmware dumps** (DSDT/SSDT `.dat`/`.aml`/`.dsl`); they are OEM-proprietary.
- If you claim a fix, say what was isolated and what wasn't.
