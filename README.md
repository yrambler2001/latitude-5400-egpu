# RX 580 eGPU on a Dell Latitude 5400 via the M.2 slot

Getting a desktop AMD GPU (Sapphire RX 580) working on a **Dell Latitude 5400** through an
**M.2 → PCIe x1 riser**, on **Windows 11**, without a DSDT override and without paid tools.

The working method uses a free **UEFI Shell** script that runs between POST and Windows. It
limits the link to Gen1, resets the slot and retrains the link. Windows then finds the GPU
at boot and sizes the root-port memory window itself.

> **Status:** working. RX 580 shows as *OK (code 0)* on the AMD driver, PCIe Gen1 x1,
> 256 MB BAR at `0xD0000000`, and no PCIe AER errors.

---

## Why this is hard on this laptop

| Symptom | Cause (short version) |
|---|---|
| Hot-plug after boot: GPU never appears | The BIOS **turns off the slot's root port at POST** if nothing is in the slot. |
| GPU powered at POST: BSOD `0xA5` (P1 `0x1000`) | Dell ACPI code maps a bogus address (`0x1_0000_5417`) when the BIOS fails to set up the GPU. |
| GPU appears after S3 sleep/wake: **Code 12** | Windows keeps the BIOS's **1 MB** root-port window and won't grow it at runtime. |
| Hot-swap in a boot-time shell: link never trains | The GPU was powered before it had a reference clock and never saw a reset after the clock appeared. |
| Link up at Gen3: thousands of WHEA-17 corrected errors | The USB-cable x1 riser can't carry 8 GT/s cleanly. |

The full chain, with evidence, is in [docs/how-it-works.md](docs/how-it-works.md).

## The method in one picture

```
 power on with an NVMe SSD in the eGPU slot     ->  BIOS keeps Root Port 00:1D.0 enabled
 F12 -> "UEFI Shell (eGPU)"                     ->  startup.nsh runs
   - limit link to Gen1 (LinkCtl2)
   - you: remove SSD, plug adapter with GPU PSU OFF, then switch PSU ON
   - Secondary Bus Reset + link disable/enable + retrain
   - log everything to \EFI\shell\egpu-log.txt
 chainload Windows Boot Manager                 ->  entry with usefirmwarepcisettings=No
 Windows enumerates the GPU at boot             ->  allocates a 256 MB window -> code 0
```

## Quick start

> Read [docs/procedure.md](docs/procedure.md) first. It explains every step and what can go wrong.

1. **Hardware**: M.2 riser with **CLKREQ# tied to GND**, and an external PSU. See [docs/hardware.md](docs/hardware.md).
2. **Firmware**: turn **Secure Boot off** (the UEFI Shell is unsigned).
3. **USB stick** (FAT32, existing content is kept). In an elevated PowerShell:
   ```powershell
   .\scripts\Install-UsbShell.ps1 -DriveLetter D
   ```
4. **Boot entries**:
   ```powershell
   .\scripts\Set-BootConfig.ps1 -UsbDriveLetter D
   ```
5. **Every boot with the eGPU**: follow [docs/procedure.md](docs/procedure.md#every-boot).
6. **Check the result**:
   ```powershell
   .\scripts\Get-EgpuStatus.ps1
   ```
7. **Undo everything**: `.\scripts\Remove-BootConfig.ps1`, then see [docs/cleanup.md](docs/cleanup.md).

## Repository layout

```
docs/
  hardware.md            parts, the CLKREQ# mod, wiring
  how-it-works.md        root-cause chain with evidence
  procedure.md           one-time setup + every-boot steps
  investigation-log.md   chronological log incl. dead ends
  dsdt-notes.md          why a DSDT override is NOT needed here, and lessons learned
  register-reference.md  PCIe registers the shell script touches
  troubleshooting.md     symptom -> check -> fix
  adapting.md            using this on other laptops / slots
  cleanup.md             how to revert every change
uefi-shell/
  startup.nsh.template   boot-time link setup script (rendered by Install-UsbShell.ps1)
  win.nsh.template       chainloads Windows Boot Manager
scripts/
  Install-UsbShell.ps1   downloads + verifies the EDK2 UEFI Shell, renders scripts onto a USB stick
  Set-BootConfig.ps1     creates the Windows boot entry and the F12 shell entry
  Get-EgpuStatus.ps1     read-only status: GPU, root-port window, link, WHEA, shell log
  Remove-BootConfig.ps1  removes what Set-BootConfig.ps1 created
```

## Tested configuration

| Item | Value |
|---|---|
| Laptop | Dell Latitude 5400 (Intel 8th-gen U, Cannon Point-LP PCH), S3 sleep |
| Slot | M.2 slot on Root Port `00:1D.0` (`8086:9DB3`, ACPI `\_SB.PCI0.RP13`) |
| GPU | Sapphire RX 580 (`1002:67DF`), Resizable-BAR capable |
| Link | USB-cable PCIe x1 riser, external PSU |
| OS | Windows 11 (build 26200) |
| UEFI Shell | EDK2 Shell 2.2, [pbatard/UEFI-Shell](https://github.com/pbatard/UEFI-Shell) release 26H1 |

## Disclaimer

This involves hot-swapping M.2 devices, writing PCIe configuration registers and changing boot
configuration. It can hang the machine, corrupt an OS install or damage hardware. **You do this at
your own risk.** Back up first. Read the scripts before running them. They are short on purpose.

## License

[MIT](LICENSE). Third-party tools (EDK2 UEFI Shell, ACPICA, AMD drivers) keep their own licenses and
are **not** redistributed here.
