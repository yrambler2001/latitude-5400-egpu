# Adapting to other laptops or slots

The method is generic. The values are not.

## 1. Find the root port and secondary bus

With the placeholder SSD (or any device) in the slot, in Windows:

```powershell
Get-PnpDevice -PresentOnly -Class System | ? FriendlyName -like '*Root Port*' |
  % { '{0}  {1}' -f $_.FriendlyName, (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_LocationInfo).Data }
```

`PCI bus 0, device 29, function 0` = `00:1D.0`. The device under it shows its own "PCI bus N";
that N is the secondary bus.

In the UEFI Shell, `pci` lists everything, and `pci 00 1D 00 -i` decodes the port.

## 2. Confirm the PCIe capability offset

In the shell: `pci <bb dd ff> -i` shows the capability list. Or `mm <prefix>40 -pci -w 1 -n`
should return `0x10`. If it's elsewhere, pass `-PcieCapOffset`.

## 3. Build the stick

```powershell
.\scripts\Install-UsbShell.ps1 -DriveLetter E -RootPort 00:1C.4 -SecondaryBus 05
# or inspect first:
.\scripts\Install-UsbShell.ps1 -Destination .\out -RootPort 00:1C.4 -SecondaryBus 05
```

## 4. Find your speed

Boot with `gen1` first. Once that works, try one step higher per boot. After 10-15 minutes of GPU
load, compare the WHEA counts from `Get-EgpuStatus.ps1`. `gen4` only makes sense if both your root
port and your GPU support 16 GT/s.

## 5. Things that may differ

- **Your BIOS may not disable empty ports.** Then you may not need the placeholder SSD.
- **You may have Modern Standby (S0ix)** instead of S3, so sleep/wake behaves differently.
- **Your PCI0 window may really be too small.** Then a DSDT window may be needed
  ([dsdt-notes.md](dsdt-notes.md)); read the lessons there first.
- **Your firmware may have a GPIO-controlled PERST# for the slot** (look for `_ON`/`_OFF` power
  resources under the root port in the DSDT/SSDTs). If so, a software PERST# pulse could replace the
  PSU power-cycle.
