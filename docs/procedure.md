# Procedure

## One-time setup

1. **Hardware mod:** CLKREQ# tied to GND on the M.2 adapter ([hardware.md](hardware.md)).
2. **BIOS:** disable **Secure Boot** (F2 → Secure Boot → Secure Boot Enable). The EDK2 UEFI Shell is unsigned.
   - BitLocker: check `manage-bde -status` first. Changing Secure Boot can trigger recovery if BitLocker is on.
     Have the recovery key ready.
3. **Clone this repo** and open an **elevated** PowerShell in it. If script execution is blocked:
   `Set-ExecutionPolicy -Scope Process Bypass`.
4. **USB stick** (FAT32):
   ```powershell
   .\scripts\Install-UsbShell.ps1 -DriveLetter D
   ```
   This downloads `shellx64.efi` (pbatard/UEFI-Shell 26H1), verifies its SHA256 and installs it as
   `\EFI\BOOT\BOOTX64.EFI`. It writes the scripts to `\EFI\shell\`. If the stick already boots
   something else, add `-ReplaceBootloader`; the old loader is kept as `BOOTX64.EFI.orig`.
   For another machine or slot, see [adapting.md](adapting.md).
5. **Windows boot entry:**
   ```powershell
   .\scripts\Set-BootConfig.ps1
   ```
   This creates **Windows 11 (eGPU)**, a copy of your current entry with `usefirmwarepcisettings No`.
   It exports the BCD store first. Your normal Windows entry is not changed.

## Every boot

| # | You do | What happens |
|---|---|---|
| 1 | Placeholder **SSD in the eGPU slot**, USB stick in, GPU PSU **off**. Power on. | BIOS sees a device in the slot and keeps Root Port `00:1D.0` enabled. |
| 2 | Press **F12**, pick the **USB stick** (e.g. "UEFI: Lexar USB Flash Drive"). | Firmware boots `\EFI\BOOT\BOOTX64.EFI` = the shell, which runs the launcher. |
| 3 | Check it prints `0x10`. | Confirms the PCIe capability is where the scripts write. |
| 4 | Type **`gen1`**, **`gen2`**, **`gen3`** or **`gen4`** and press Enter. | Sets the root port's Target Link Speed and reads it back. |
| 5 | Remove the SSD. Plug in the eGPU adapter. **Then** switch the PSU on. Wait 5 s. Press a key. | GPU powers up with the reference clock already present. |
| 6 | Read the GPU check. | `02 10 DF 67` = the RX 580 answers. Link Status `0x7…` = up. |
| 6a | If it shows **`FF FF`**: press **`q`**, PSU **off 5 s, on 5 s**, type **`again`**. Repeat as needed. | `again.nsh` re-checks without touching the link. |
| 7 | Press a key. At the Windows menu pick **Windows 11 (eGPU)**. | `win.nsh` chainloads `bootmgfw.efi`. |
| 8 | Log in. Run `.\scripts\Get-EgpuStatus.ps1`. | Expect: RX 580 `OK problem=0`, a 256 MB window, few or no WHEA events. |

**Don't use sleep (S3)** with the eGPU attached. Resume restores the BIOS's 1 MB window and
Gen3, which brings back Code 12 and link errors. Shut down instead.

## Choosing the speed

| Choice | Tested result on the reference setup |
|---|---|
| `gen1` | Works. **0** WHEA events. |
| `gen2` | Works. **12** WHEA events at idle after boot; not yet measured under sustained load. |
| `gen3` | Link comes up (via S3 wake), but ~6,000 corrected errors per minute. Not usable on this riser. |
| `gen4` | Not supported by the Cannon Point root port or the RX 580; included for other hardware. |

Measure it on your own setup: run a GPU load for 10-15 minutes, then check the WHEA count in
`Get-EgpuStatus.ps1`. Go down one step if it climbs into the hundreds.
