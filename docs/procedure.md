# Procedure

## One-time setup

1. **Hardware mod:** CLKREQ# tied to GND on the M.2 adapter ([hardware.md](hardware.md)).
2. **BIOS:** disable **Secure Boot** (F2 → Secure Boot → Secure Boot Enable). The EDK2 UEFI Shell is unsigned.
   - BitLocker: check `manage-bde -status` first. Changing Secure Boot can trigger recovery if BitLocker is on.
     Have the recovery key ready.
3. **Clone this repo** and open an **elevated** PowerShell in it. If script execution is blocked:
   `Set-ExecutionPolicy -Scope Process Bypass`.
4. **USB stick** (FAT32; other content is kept):
   ```powershell
   .\scripts\Install-UsbShell.ps1 -DriveLetter D
   ```
   This downloads `shellx64.efi` (pbatard/UEFI-Shell 26H1), verifies its SHA256, and writes
   `\EFI\shell\{shellx64.efi,startup.nsh,win.nsh}`.
   For another machine or slot, see [adapting.md](adapting.md).
5. **Boot entries:**
   ```powershell
   .\scripts\Set-BootConfig.ps1 -UsbDriveLetter D
   ```
   This creates:
   - **Windows 11 (eGPU)**: a copy of your current entry with `usefirmwarepcisettings No`.
   - **UEFI Shell (eGPU)**: an F12 firmware entry pointing at the stick.

   It exports the BCD store first. Your normal Windows entry is not changed.

## Every boot

| # | You do | What happens |
|---|---|---|
| 1 | Placeholder **SSD in the eGPU slot**, USB stick in, GPU PSU **off**. Power on. | BIOS sees a device in the slot and keeps Root Port `00:1D.0` enabled. |
| 2 | Press **F12**, pick **UEFI Shell (eGPU)**. | Shell starts and runs `startup.nsh`. |
| 3 | Check it prints `0x10`. | Confirms the PCIe capability is where the script writes. |
| 4 | — | Script logs the state and sets Link Control 2 → **Gen1**. |
| 5 | Remove the SSD. Plug in the eGPU adapter. **Then** switch the PSU on. Wait 5 s. Press a key. | GPU powers up with the reference clock already present. |
| 6 | — | Script logs, does a Secondary Bus Reset and link disable/enable/retrain, and prints the GPU check (`1002` = AMD). |
| 7 | Press a key. At the Windows menu pick **Windows 11 (eGPU)**. | `win.nsh` chainloads `bootmgfw.efi`. |
| 8 | Log in. Run `.\scripts\Get-EgpuStatus.ps1`. | Expect: RX 580 `OK problem=0`, a 256 MB window, 0 WHEA events. |

**Don't use sleep (S3)** with the eGPU attached. Resume restores the BIOS's 1 MB window and Gen3,
which brings back Code 12 and link errors. Shut down instead.

## If the GPU check in step 6 shows `FF FF FF FF`

- Power-cycle the PSU (off, 5 s, on), then run `startup.nsh` again from the shell prompt
  (`q` to stop the current run first).
- See [troubleshooting.md](troubleshooting.md). Everything is in `\EFI\shell\egpu-log.txt`.
