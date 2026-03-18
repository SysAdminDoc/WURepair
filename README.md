# WURepair

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11-blue?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/Language-PowerShell-5391FE?style=for-the-badge&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/Version-2.0.0-orange?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License">
</p>

<p align="center">
  <b>Comprehensive Windows Update Repair Tool</b><br>
  <i>Fix Windows Update when nothing else works</i>
</p>

---

## Overview

**WURepair** is a comprehensive repair tool that fixes Windows Update issues caused by privacy tools, malware, system corruption, or misconfiguration. It goes beyond basic troubleshooting by addressing root causes like hosts file blocks, disabled services, SSL/TLS misconfigurations, and blocking policies.

If you've run tools like [privacy.sexy](https://privacy.sexy), O&O ShutUp10, or Windows debloaters and now Windows Update won't work, this tool can help restore functionality.

## Features

### 🌐 Network & Connectivity Repairs
- **Hosts File Cleanup**: Removes blocks for 25+ Microsoft update domains
- **SSL/TLS Repair**: Enables TLS 1.2, configures .NET for strong cryptography
- **Firewall Rules**: Removes blocking rules, ensures update services are allowed
- **Winsock/TCP Reset**: Full network stack reset
- **Proxy Cleanup**: Clears proxy settings that may interfere

### ⚙️ Service Repairs
- **BITS Repair**: Fixes Background Intelligent Transfer Service dependencies and configuration
- **Delivery Optimization**: Re-enables if disabled by privacy tools
- **Service Dependencies**: Ensures RpcSs, EventSystem, SystemEventsBroker are running
- **Correct Start Types**: Resets all update services to proper configurations

### 📋 Policy & Registry Repairs
- **Removes Blocking Policies**: Clears 10+ registry values that disable Windows Update
- **WSUS Detection**: Identifies misconfigured WSUS server redirections
- **Registry Cleanup**: Removes stuck reboot flags and pending update markers
- **Group Policy Refresh**: Forces policy update after changes

### 🔧 System Repairs
- **SoftwareDistribution Reset**: Backs up and clears update cache
- **Catroot2 Reset**: Clears cryptographic catalog cache
- **DLL Re-registration**: Re-registers 35+ Windows Update DLLs
- **DISM Integration**: Repairs component store corruption
- **SFC Integration**: Scans and repairs system file integrity

### 📊 Diagnostics
- **Pre-repair Analysis**: Full system diagnostic before making changes
- **Connectivity Testing**: Tests all Microsoft update endpoints
- **LTSC/IoT Detection**: Identifies editions with limited update availability
- **Post-repair Verification**: Confirms fixes were successful

## Screenshots

<p align="center">
  <i>Diagnostics Output</i>
</p>

```
    ╦ ╦╦ ╦  ╦═╗┌─┐┌─┐┌─┐┬┬─┐
    ║║║║ ║  ╠╦╝├┤ ├─┘├─┤│├┬┘
    ╚╩╝╚═╝  ╩╚═└─┘┴  ┴ ┴┴┴└─
    Windows Update Repair Tool v2.0

======================================================================
  DIAGNOSTICS - Gathering System Information
======================================================================
    OS: Microsoft Windows 11 Pro (10.0.22631) Build 22631
    Architecture: 64-bit
    System Drive: 150.32 GB free of 476.94 GB

    Windows Update Service Status:
      Windows Update: Stopped (Manual)
      Background Intelligent Transfer Service: Running (Manual)
      Cryptographic Services: Running (Automatic)
      Delivery Optimization: Running (Automatic)

[+] No pending reboot detected
[+] No Microsoft blocks in hosts file

======================================================================
  CONNECTIVITY - Testing Windows Update Servers
======================================================================
[+] Windows Update: Reachable
[+] Microsoft Update: Reachable
[+] Download Center: Reachable
[+] Windows Update Catalog: Reachable
[+] Delivery Optimization: Reachable
```

## Requirements

- **OS**: Windows 10 / Windows 11 (all editions including LTSC/IoT)
- **Privileges**: Administrator
- **PowerShell**: 5.1 or later (included with Windows)
- **Disk Space**: At least 5 GB free recommended

## Installation

1. Download `WURepair.ps1` from the [Releases](../../releases) page
2. Save to a convenient location (e.g., Desktop)

## Usage

### Method 1: Right-Click Run
1. Right-click `WURepair.ps1`
2. Select **Run with PowerShell**
3. If prompted by UAC, click **Yes**

### Method 2: PowerShell Direct
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\WURepair.ps1
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-Quick` | Skip DISM and SFC scans (faster, less thorough) |
| `-SkipDISM` | Skip only DISM component store repair |
| `-SkipSFC` | Skip only System File Checker |
| `-SkipBackup` | Skip backup of Windows Update folders |
| `-Help` | Display help information |

### Examples

```powershell
# Full repair (recommended)
.\WURepair.ps1

# Quick repair - skip lengthy scans
.\WURepair.ps1 -Quick

# Skip only DISM
.\WURepair.ps1 -SkipDISM

# Skip backup (if low on disk space)
.\WURepair.ps1 -SkipBackup
```

## What Gets Fixed

### Hosts File Domains Unblocked
The tool removes blocks for these Microsoft domains (and more):

| Domain | Purpose |
|--------|---------|
| `update.microsoft.com` | Windows Update service |
| `download.windowsupdate.com` | Update downloads |
| `download.delivery.mp.microsoft.com` | Delivery Optimization |
| `ctldl.windowsupdate.com` | Certificate Trust List |
| `settings-win.data.microsoft.com` | Windows settings sync |

### Registry Policies Removed

| Policy | Location |
|--------|----------|
| `DisableWindowsUpdateAccess` | Blocks WU UI access |
| `DoNotConnectToWindowsUpdateInternetLocations` | Blocks online updates |
| `NoAutoUpdate` | Disables automatic updates |
| `UseWUServer` | Forces WSUS (when misconfigured) |
| `SetDisableUXWUAccess` | Hides update settings |

### Services Repaired

| Service | Default State |
|---------|---------------|
| `wuauserv` (Windows Update) | Manual |
| `bits` (BITS) | Manual (Delayed Start) |
| `cryptsvc` (Cryptographic Services) | Automatic |
| `dosvc` (Delivery Optimization) | Automatic (Delayed Start) |
| `msiserver` (Windows Installer) | Manual |
| `TrustedInstaller` (Modules Installer) | Manual |

## Troubleshooting

### "Script won't run" / Execution Policy Error
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

### Still getting 403 Forbidden errors after repair
- Check for third-party firewall software (Norton, McAfee, etc.)
- Disable VPN temporarily
- Check corporate proxy settings
- Run the script again after restart

### BITS service still won't start
1. Restart your computer
2. Run the script again
3. If still failing, check Event Viewer for BITS errors

### Updates found but won't install
- Ensure at least 10 GB free disk space
- Try installing updates one at a time
- Run `DISM /Online /Cleanup-Image /RestoreHealth` manually

### LTSC/IoT Edition - Limited Updates
Windows 10/11 LTSC and IoT editions only receive security updates. Feature updates are not available. This is by design, not a bug.

## Files Created

| File | Location | Purpose |
|------|----------|---------|
| `WURepair_[timestamp].log` | Desktop | Detailed operation log |
| `SoftwareDistribution.bak.[timestamp]` | C:\Windows | Backup of update cache |
| `catroot2.bak.[timestamp]` | C:\Windows\System32 | Backup of crypto cache |
| `hosts.backup.[timestamp]` | C:\Windows\System32\drivers\etc | Backup of hosts file |

## Recovery

If something goes wrong:

1. **System Restore**: The script creates a restore point before making changes
2. **Registry Backups**: Original registry values are logged
3. **Folder Backups**: SoftwareDistribution and catroot2 are renamed, not deleted
4. **Hosts Backup**: Original hosts file is preserved with timestamp

To restore the hosts file manually:
```powershell
Copy-Item "C:\Windows\System32\drivers\etc\hosts.backup.[timestamp]" "C:\Windows\System32\drivers\etc\hosts" -Force
```

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        WURepair Flow                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Create System Restore Point                                 │
│  2. Run Diagnostics (OS, services, disk, connectivity)         │
│  3. Repair Hosts File (remove Microsoft blocks)                 │
│  4. Repair SSL/TLS (enable TLS 1.2, strong crypto)             │
│  5. Repair Firewall Rules (allow update traffic)               │
│  6. Repair Service Dependencies (BITS, DO)                      │
│  7. Remove Blocking Policies (registry cleanup)                 │
│  8. Stop Update Services                                        │
│  9. Backup & Clear Caches (SoftwareDistribution, catroot2)     │
│ 10. Re-register DLLs (35+ Windows Update DLLs)                 │
│ 11. Reset Network Stack (Winsock, TCP/IP, DNS, proxy)          │
│ 12. Reset Windows Update Agent                                  │
│ 13. Run DISM (component store repair)                          │
│ 14. Run SFC (system file check)                                │
│ 15. Start Update Services                                       │
│ 16. Refresh Group Policy                                        │
│ 17. Post-Repair Connectivity Test                               │
│ 18. Trigger Update Scan                                         │
└─────────────────────────────────────────────────────────────────┘
```

## Privacy & Safety

- ✅ **No data collection** - Everything runs locally
- ✅ **No external downloads** - Uses only built-in Windows tools
- ✅ **Open source** - Full source code available for review
- ✅ **Creates backups** - All changes can be reversed
- ✅ **Restore point** - System restore point created automatically
- ✅ **Detailed logging** - Full audit trail saved to Desktop

## Contributing

Contributions are welcome! If you encounter a Windows Update issue that WURepair doesn't fix:

1. Run the script and save the log file
2. Note any error messages
3. Open an issue with the log and description

## Changelog

### v2.0.0
- Added hosts file cleanup for Microsoft domains
- Added SSL/TLS configuration repair
- Added firewall rules repair
- Added service dependency repair (BITS, Delivery Optimization)
- Added Windows Update policy removal
- Added post-repair connectivity verification
- Added LTSC/IoT edition detection
- Improved service start logic (checks for disabled state)
- Better error messages with actionable guidance

### v1.0.0
- Initial release
- Basic service stop/start
- Cache clearing
- DLL re-registration
- DISM/SFC integration

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This tool modifies Windows system settings, registry values, and network configuration. While it creates backups and is designed to be safe:

- **Use at your own risk**
- **Always have backups** of important data
- **Test in a VM first** if unsure
- **A restart is required** after running
- The author is not responsible for any issues arising from use of this tool

## Related Tools

- [DefenderShield](../DefenderShield) - Repair Windows Defender and Firewall after privacy tools disable them

---

<p align="center">
  Made with ☕ by Matt
</p>
