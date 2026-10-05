# UEFI Shell scripts

These run on the **EDK2 UEFI Shell** between POST and Windows. They are templates:
`scripts/Install-UsbShell.ps1` fills in the `{{TOKENS}}` and builds this layout on a FAT32 stick:

```
\EFI\BOOT\BOOTX64.EFI     the UEFI Shell: what firmware boots when you pick the stick in F12
\EFI\BOOT\startup.nsh     launcher (from launcher.nsh.template)
\startup.nsh              same launcher (fallback; some shells look at the volume root)
\EFI\shell\startup.nsh    logs, checks the root port, shows the speed menu
\EFI\shell\gen1..gen4.nsh speed choices (generated) -> flow.nsh 01..04
\EFI\shell\flow.nsh       sets Target Link Speed, guides the swap, then again.nsh
\EFI\shell\again.nsh      checks the GPU without touching the link; repeat after a PSU power-cycle
\EFI\shell\win.nsh        chainloads Windows Boot Manager
\EFI\shell\egpu-log.txt   appended by every script
```

## Flow

```
startup.nsh ── menu ──► (you type) gen2 ──► flow.nsh 02 ──► swap prompt ──► again.nsh
                                                                 ▲              │ GPU shown -> win.nsh
                                                                 └── PSU off/on ┘ FF FF -> q, type "again"
```

## Tokens

| Token | Meaning | Latitude 5400 value |
|---|---|---|
| `{{RP}}` | `mm -pci` address prefix `ssssbbddff` of the root port | `0000001D00` |
| `{{RP_PCI}}` | Same port in `pci` command form `bb dd ff` | `00 1D 00` |
| `{{SECBUS}}` | Secondary bus number (where the GPU shows up) | `02` |
| `{{CAP}}` | Offset of the PCI Express capability | `40` |
| `{{LSTA}}` / `{{LCTL2}}` | Link Status / Link Control 2 (`CAP+0x12` / `CAP+0x30`) | `52` / `70` |
| `{{WIN_ENTRY}}` | Name of the Windows boot entry to pick | `Windows 11 (eGPU)` |

Register details are in [../docs/register-reference.md](../docs/register-reference.md).

## Shell syntax notes

- `mm <addr> -pci -w 1 -n` reads one byte. `mm <addr> <val> -pci -w 1 -n` writes it without prompting.
  The `-pci` address format is `ssssbbddffrr` (segment, bus, device, function, register).
- `%1` is the first argument passed to a script (`flow.nsh 02` → `%1` = `02`).
- `>>a file` appends ASCII output, and `2>>a file` does the same for errors.
- `pause` waits for a key; `q` aborts the script and returns to the `Shell>` prompt.
- Typing a script name without `.nsh` normally works. If it doesn't, type `gen2.nsh` / `again.nsh`.
- There's no command to read typed input into a variable. That's why the speed is chosen by typing
  a script name.
