# RX 580 eGPU on a Dell Latitude 5400 via the M.2 slot

Getting a desktop AMD GPU (Sapphire RX 580) working on a **Dell Latitude 5400** through an
**M.2 → PCIe x1 riser**, on **Windows 11**, without a DSDT override and without paid tools.

The working method is a **USB stick that boots the free EDK2 UEFI Shell**. A small script runs
there, between POST and Windows: it sets the link speed (you choose Gen1-Gen4), guides you
through attaching the GPU, and checks that it answers. Windows then finds the GPU at boot and
sizes the root-port memory window itself.

> **Status:** working. The RX 580 shows as *OK (code 0)* on the AMD driver, with a 256 MB BAR at
> `0xD0000000`.
> - **Gen1 x1:** 0 PCIe AER errors.
> - **Gen2 x1:** 12 errors at idle; sustained load not yet measured.

---

## Why this is hard on this laptop

| Symptom | Cause (short version) |
|---|---|
| Hot-plug after boot: GPU never appears | The BIOS **turns off the slot's root port at POST** if nothing is in the slot. |
| GPU powered at POST: BSOD `0xA5` (P1 `0x1000`) | Dell ACPI code maps a bogus address (`0x1_0000_5417`) when the BIOS fails to set up the GPU. |
| GPU appears after S3 sleep/wake: **Code 12** | Windows keeps the BIOS's **1 MB** root-port window and won't grow it at runtime. |
| GPU attached in the boot-time shell: sometimes no link | The GPU didn't get a clean power-on reset. **Power-cycling its PSU** fixes it; software resets never did. |
| Link up at Gen3: thousands of WHEA-17 corrected errors | The USB-cable x1 riser can't carry 8 GT/s cleanly. |

The full chain, with evidence, is in [docs/how-it-works.md](docs/how-it-works.md).

## The method in one picture

```
 power on with an NVMe SSD in the eGPU slot    ->  BIOS keeps Root Port 00:1D.0 enabled
 F12 -> pick the USB stick                     ->  UEFI Shell (\EFI\BOOT\BOOTX64.EFI) starts
   - type gen1 / gen2 / gen3 / gen4            ->  Target Link Speed set on the root port
   - you: remove SSD, plug adapter with GPU PSU OFF, then switch PSU ON
   - GPU check: 02 10 DF 67 = OK   |   FF FF = PSU off/on, type "again"
   - everything logged to \EFI\shell\egpu-log.txt
 chainload Windows Boot Manager                ->  entry with usefirmwarepcisettings=No
 Windows enumerates the GPU at boot            ->  allocates a 256 MB window -> code 0
```

## Quick start

> Read [docs/procedure.md](docs/procedure.md) first. It explains every step and what can go wrong.

1. **Hardware**: M.2 riser with **CLKREQ# tied to GND**, and an external PSU. See [docs/hardware.md](docs/hardware.md).
2. **Firmware**: turn **Secure Boot off** (the UEFI Shell is unsigned).
3. **USB stick** (FAT32). In an elevated PowerShell:
   ```powershell
   .\scripts\Install-UsbShell.ps1 -DriveLetter D
   ```
4. **Windows boot entry** (once):
   ```powershell
   .\scripts\Set-BootConfig.ps1
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
  hardware.md            parts, the CLKREQ# mod, power order
  how-it-works.md        root-cause chain with evidence
  procedure.md           one-time setup + every-boot steps + choosing the speed
  investigation-log.md   chronological log incl. dead ends
  dsdt-notes.md          why a DSDT override is NOT needed here, and lessons learned
  register-reference.md  PCIe registers the shell scripts touch
  troubleshooting.md     symptom -> check -> fix
  adapting.md            using this on other laptops / slots
  cleanup.md             how to revert every change
uefi-shell/
  *.nsh.template         startup (menu), flow (speed + swap), again (check), win, launcher
scripts/
  Install-UsbShell.ps1   downloads + verifies the EDK2 UEFI Shell, builds the bootable stick
  Set-BootConfig.ps1     creates the Windows boot entry (usefirmwarepcisettings No)
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

This involves hot-swapping M.2 devices, writing a PCIe configuration register and changing
boot configuration. It can hang the machine, corrupt an OS install or damage hardware. **You do
this at your own risk.** Back up first. Read the scripts before running them. They are short on
purpose.

## License

[MIT](LICENSE). Third-party tools (EDK2 UEFI Shell, ACPICA, AMD drivers) keep their own licenses and
are **not** redistributed here.
