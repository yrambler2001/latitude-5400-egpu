# UEFI Shell scripts

These run on the **EDK2 UEFI Shell** between POST and Windows. They are templates:
`scripts/Install-UsbShell.ps1` fills in the `{{TOKENS}}` and copies the results to
`\EFI\shell\` on a USB stick.

| File | Role |
|---|---|
| `startup.nsh.template` | Runs automatically when the shell starts. Logs, limits the link to Gen1, waits for the swap, resets and retrains the link. |
| `win.nsh.template` | Finds `\EFI\Microsoft\Boot\bootmgfw.efi` on any `fsN:` and starts it. |

## Tokens

| Token | Meaning | Latitude 5400 value |
|---|---|---|
| `{{RP}}` | `mm -pci` address prefix `ssssbbddff` of the root port | `0000001D00` |
| `{{RP_PCI}}` | Same port in `pci` command form `bb dd ff` | `00 1D 00` |
| `{{SECBUS}}` | Secondary bus number (where the GPU shows up) | `02` |
| `{{CAP}}` | Offset of the PCI Express capability | `40` |
| `{{LCTL}}` / `{{LSTA}}` / `{{LCTL2}}` | Link Control / Link Status / Link Control 2 (`CAP+0x10/+0x12/+0x30`) | `50` / `52` / `70` |
| `{{BCTL_ORIG}}` | Root port Bridge Control value to restore after the reset | `10` |
| `{{BCTL_SBR}}` | Same value with bit 6 (Secondary Bus Reset) set | `50` |
| `{{LCTL_EN}}` | Link Control written back: Common Clock on, ASPM off | `40` |
| `{{LCTL_DIS}}` | `LCTL_EN` + Link Disable (bit 4) | `50` |
| `{{LCTL_RT}}` | `LCTL_EN` + Retrain Link (bit 5) | `60` |
| `{{WIN_ENTRY}}` | Name of the Windows boot entry to pick | `Windows 11 (eGPU)` |

Register details are in [../docs/register-reference.md](../docs/register-reference.md).

## Shell syntax notes

- `mm <addr> -pci -w 1 -n` reads one byte. `mm <addr> <val> -pci -w 1 -n` writes it without prompting.
  The `-pci` address format is `ssssbbddffrr` (segment, bus, device, function, register).
- `>>a file` appends ASCII output. `2>>a file` does the same for errors.
- `stall N` waits N **microseconds**.
- `pause` waits for a key. `q` aborts the script.
- The shell runs `startup.nsh` from the folder the shell binary was loaded from. If it doesn't, run
  `fsN:` then `cd \EFI\shell` then `startup.nsh` by hand.
