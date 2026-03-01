# Disable USB Power Saving (Windows)

A PowerShell script that disables two Windows USB power-saving features — Selective Suspend and USB 3.0 Link Power Management (U1/U2) — that are known to cause random device disconnections on certain hub controllers.

## The Problem

USB devices (audio interfaces, mice, keyboards, DACs, etc.) randomly disconnect and reconnect, or disappear entirely until you replug them. The devices are still physically connected and powered on — Windows just stops seeing them.

This is especially common with:
- USB hubs (particularly budget hubs using Realtek controllers)
- Cascaded hubs (hub behind a hub, or hub behind a KVM switch)
- USB audio devices (isochronous transfers have timing gaps that can be misread as idle)
- USB 3.0 devices behind USB 3.0 hubs

## Root Cause

Two independent Windows power-saving features can cause this:

### 1. USB Selective Suspend

Windows can [suspend individual USB hub ports](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-selective-suspend) to save power. When a hub controller has buggy firmware, it fails to properly re-enumerate downstream devices when waking the port back up. The devices appear as disconnected even though they're still physically connected and powered.

Selective suspend operates at the **hub controller level**, not individual devices. When a hub controller suspends, all downstream devices can lose connection at once.

> *"The USB selective suspend feature allows the hub driver to suspend an individual port without affecting the operation of the other ports on the hub."*
> — [Microsoft: USB Selective Suspend](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-selective-suspend)

### 2. USB 3.0 Link Power Management (U1/U2 States)

The USB 3.0 specification defines [U1 and U2 low-power link states](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-3-0-lpm-mechanism-) that operate **independently of Selective Suspend**. After a link is idle for a short period, hardware autonomously transitions the link into U1 (fast-exit standby) or U2 (slower-exit standby) without any software involvement.

The key issue: **this transition is handled entirely by hardware/firmware**. If the hub controller's U1/U2 implementation is buggy, the link enters an error state and the device is re-enumerated or dropped entirely.

> *"After the software configures the link partners for U1 or U2 transition, the hardware enters the states autonomously without any software intervention."*
> — [Microsoft: USB 3.0 LPM Mechanism](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-3-0-lpm-mechanism-)

Microsoft documents these issues extensively in [Common Hardware Problems With U1 or U2 Implementation](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/common-hardware-problems-with-u1-or-u2-implementation), including:

- Devices failing to send `Ping.LPFS` in U1, causing the link partner to assume the device was removed
- Hubs failing to transition their upstream port from U1 to U2 correctly
- Hubs failing to handle U1/U2 to U3 transitions, causing the link to enter an error state and trigger re-enumeration

### Why This Setting is Hidden

The U1/U2 Link Power Management setting exists in Windows power options but is **hidden by default** (`ATTRIB_HIDE`). Most users never know it exists, and it can remain enabled even when USB Selective Suspend is disabled — which is why disabling only Selective Suspend often doesn't fully fix the problem.

### Why This Mostly Affects Windows

Linux's `xhci_hcd` driver handles U1/U2 transitions with more robust retry/recovery logic, and many distributions disable U1/U2 by default for external hubs. The same hardware that drops devices on Windows often works flawlessly on Linux.

## What This Script Does

`Disable-USBPowerManagement.ps1`:

1. **Unhides** the USB 3.0 Link Power Management setting (so it can be queried and modified)
2. **Enumerates all power plans** on the system (not just the active one)
3. **Disables USB Selective Suspend** (AC and DC) on every plan
4. **Disables USB 3.0 Link Power Management / U1/U2** (AC and DC) on every plan
5. **Reactivates** the current power plan to apply changes immediately

The script is idempotent — it checks current values before writing and only makes changes if needed.

## Usage

### One-Time Run

Run in an elevated (Administrator) PowerShell:

```powershell
.\Disable-USBPowerManagement.ps1
```

### Persistent (Survives Windows Update)

Windows Update can silently re-enable these power settings. To guard against that, install a scheduled task that re-applies the changes at every logon:

```powershell
.\Install-ScheduledTask.ps1
```

This creates a scheduled task called "Disable USB Power Management" that:
- Runs at every user logon
- Runs as SYSTEM with highest privileges
- Runs hidden (no console window)
- Has a 5-minute execution timeout

### Verify Settings

To check the current state of both settings on your active power plan:

```powershell
# USB Selective Suspend (0x00 = disabled)
powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226

# USB 3.0 Link Power Management (0x00 = off)
powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009
```

## Power Plan GUIDs Reference

The script uses these standard Windows GUIDs (identical on every Windows installation):

| GUID | Description |
|------|-------------|
| `2a737441-1930-4402-8d77-b2bebba308a3` | USB Settings subgroup |
| `48e6b7a6-50f5-4782-a5d4-53bb8f07e226` | USB Selective Suspend setting |
| `d4e98f31-5ffe-4ce1-be31-1b38b384c009` | USB 3 Link Power Management setting |

These are Microsoft-defined constants built into every Windows 10/11 installation. You can list all power setting aliases with `powercfg /aliases`.

## Requirements

- Windows 10 or Windows 11
- Administrator privileges (PowerShell "Run as Administrator")
- PowerShell 5.1+ (included with Windows 10/11)

## Additional Tips

If you're still experiencing disconnects after running this script, consider:

- **Check your hub's controller chip.** Budget hubs using Realtek (e.g., RTS5411) are most prone to suspend/resume failures. Hubs using VIA Labs (VL812, VL817) or Texas Instruments chips are usually more reliable.
- **Reduce hub cascade depth.** USB spec allows up to 7 tiers, but fewer hubs in the chain means fewer points of failure.
- **Check PCIe ASPM.** If your USB controller is on PCIe, Link State Power Management (`PCI Express > Link State Power Management` in power options) can cause similar issues at the host controller level.

## References

- [Microsoft: USB Selective Suspend](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-selective-suspend) — Official documentation on how selective suspend works at the hub driver level
- [Microsoft: USB 3.0 Link Power Management (LPM) Mechanism](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-3-0-lpm-mechanism-) — U1/U2 state definitions and how hardware transitions are autonomous
- [Microsoft: Common Hardware Problems With U1 or U2 Implementation](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/common-hardware-problems-with-u1-or-u2-implementation) — Documented hub/controller bugs that cause device disconnections
- [Microsoft: U1 and U2 Transitions](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/u1-and-u2-transitions) — Detailed transition mechanics and packet deferring
- [Microsoft: Powercfg Command-Line Options](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options) — Documentation for all `powercfg` commands used in this script

