<p align="center"><img src="icon.svg" width="128" height="128" alt="WURepair"></p>

# WURepair

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11-blue?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/Language-PowerShell-5391FE?style=for-the-badge&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/Version-2.11.0-orange?style=for-the-badge" alt="Version">
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
- **WaaS / USO Repair**: Resets Update Orchestrator services and re-enables disabled USO scheduled tasks
- **Delivery Optimization Reset**: Clears Delivery Optimization cache and removes stale download-mode policy values

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
- **Component Store Analysis**: Parses `DISM /AnalyzeComponentStore` and uses `/ResetBase` only when cleanup is recommended and reclaimable data is at least 1024 MB
- **Servicing Stack Preflight**: Optional `-StageSSU` path downloads and installs an applicable Servicing Stack Update before DISM
- **Catalog SSU Repair**: Optional `-RepairServicingStack` searches Microsoft Update Catalog, downloads the newest matching SSU `.msu`, and retries the next match if `wusa.exe` returns `0x800f0922`
- **SFC Integration**: Scans and repairs system file integrity

### 📊 Diagnostics & Verification
- **Diagnostic Pre-Check Report**: Formatted status table showing service states, folder sizes, DISM health, pending reboot status, last successful update date, and last 5 Windows Update errors from event log
- **Ranked HRESULT Summary**: Parses `%WINDIR%\WindowsUpdate.log` and converted Windows Update ETW traces into the top 10 recurring error codes with Microsoft reference links
- **WaaSMedic & Delivery Optimization Health**: Surfaces Windows Update Medic service state, recent medic warnings/errors, Delivery Optimization peer cache health, active jobs, peer counts, and transfer byte totals
- **Update Health Tools Detection**: Detects Microsoft Update Health Tools / Windows Remediation presence, `uhssvc`, `sedsvc`, `sedlauncher`, remediation processes, and `rempl` scheduled tasks
- **WSUS / SUP Posture**: Resolves `WUServer` / `WUStatusServer`, target group, `UseWUServer`, dual-scan, and policy-driven update-source settings
- **Connectivity Testing**: Tests all Microsoft update endpoints
- **LTSC/IoT Detection**: Identifies editions with limited update availability
- **Post-repair Before/After Comparison**: Re-runs diagnostic check after repairs and displays side-by-side comparison table
- **JSON RMM Report**: Optional `-JsonReport <path>` writes pre/post diagnostics, changed fields, service deltas, phase results, and run metadata
- **Progress Tracking**: Phase-by-phase progress bar with percentage (`Write-Progress`)
- **Event Log Integration**: Writes repair summary to Windows Application event log (Source: `WURepair`) for RMM tool detection
- **Selective Repair**: Run individual phases via `-RepairServices`, `-RepairDLLs`, `-RepairStore`, `-RepairDISM`, `-RepairSFC`, `-RepairNetwork`, `-RepairWaaS`, `-RepairDelivery`

## Screenshots

<p align="center">
  <i>Diagnostics Output</i>
</p>

```
    ╦ ╦╦ ╦  ╦═╗┌─┐┌─┐┌─┐┬┬─┐
    ║║║║ ║  ╠╦╝├┤ ├─┘├─┤│├┬┘
    ╚╩╝╚═╝  ╩╚═└─┘┴  ┴ ┴┴┴└─
    Windows Update Repair Tool v2.11.0

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
| `-StageSSU` | Before DISM, download and install an applicable Servicing Stack Update through Windows Update Agent |
| `-JsonReport <path>` | Write pre/post diagnostic delta as machine-parseable JSON |
| `-Help` | Display help information |

### Selective Repair Switches

Run individual repair phases instead of the full pipeline:

| Switch | Description |
|--------|-------------|
| `-RepairServices` | Only reset/restart Windows Update services |
| `-RepairDLLs` | Only re-register Windows Update DLLs |
| `-RepairStore` | Only rename SoftwareDistribution/catroot2 |
| `-RepairDISM` | Only run DISM component store repair |
| `-RepairSFC` | Only run System File Checker |
| `-RepairNetwork` | Only reset network stack |
| `-RepairWaaS` | Only reset Update Orchestrator services and USO tasks |
| `-RepairDelivery` | Only reset Delivery Optimization cache and download mode |
| `-RepairServicingStack` | Only download and install a matching Microsoft Update Catalog SSU package |
| `-RepairAll` | Run all phases (default when no switch given) |

Switches can be combined (e.g., `-RepairStore -RepairDLLs`).

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

# Only reset services
.\WURepair.ps1 -RepairServices

# Reset data stores + re-register DLLs
.\WURepair.ps1 -RepairStore -RepairDLLs

# Run DISM with Servicing Stack Update preflight
.\WURepair.ps1 -RepairDISM -StageSSU

# Repair Servicing Stack directly from Microsoft Update Catalog
.\WURepair.ps1 -RepairServicingStack

# Full repair with RMM-readable JSON report
.\WURepair.ps1 -JsonReport C:\Temp\WURepair-report.json
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
│                      WURepair v2.11.0 Flow                      │
├─────────────────────────────────────────────────────────────────┤
│  1. Diagnostic Pre-Check Report (status table)                  │
│  2. Create System Restore Point                                 │
│  3. Run Diagnostics (OS, services, disk, connectivity)         │
│  4. Repair Hosts File (remove Microsoft blocks)                 │
│  5. Repair SSL/TLS (enable TLS 1.2, strong crypto)             │
│  6. Repair Firewall Rules (allow update traffic)               │
│  7. Repair Service Dependencies (BITS, DO)                      │
│  8. Remove Blocking Policies (registry cleanup)                 │
│  9. Stop Update Services                                        │
│ 10. Backup & Clear Caches (SoftwareDistribution, catroot2)     │
│ 11. Re-register DLLs (35+ Windows Update DLLs)                 │
│ 12. Reset Network Stack (Winsock, TCP/IP, DNS, proxy)          │
│ 13. Reset Windows Update Agent                                  │
│ 14. Optional SSU staging before DISM (-StageSSU)                │
│ 15. Optional Catalog SSU repair (-RepairServicingStack)         │
│ 16. Run DISM + analyzed component cleanup                      │
│ 17. Run SFC (system file check)                                │
│ 18. Start Update Services                                       │
│ 19. Refresh Group Policy                                        │
│ 20. Post-Repair Connectivity Test                               │
│ 21. Post-Repair Verification (before/after comparison)          │
│ 22. Trigger Update Scan                                         │
│ 23. Write Event Log Summary / optional JSON report              │
└─────────────────────────────────────────────────────────────────┘
```

## Privacy & Safety

- ✅ **No data collection** - Everything runs locally
- ✅ **No external downloads by default** - `-StageSSU` and `-RepairServicingStack` are opt-in update download paths
- ✅ **Open source** - Full source code available for review
- ✅ **Creates backups** - Cache and registry repairs can be reversed; `/ResetBase` is intentionally permanent for superseded updates
- ✅ **Restore point** - System restore point created automatically
- ✅ **Detailed logging** - Full audit trail saved to Desktop

## Contributing

Contributions are welcome! If you encounter a Windows Update issue that WURepair doesn't fix:

1. Run the script and save the log file
2. Note any error messages
3. Open an issue with the log and description

## Changelog

### v2.11.0
- Added optional `-JsonReport <path>` output for RMM ingestion
- JSON reports include run metadata, options, phase results, pre/post diagnostics, changed fields, and service deltas

### v2.10.0
- Added optional `-RepairServicingStack` Microsoft Update Catalog SSU repair path
- Catalog repair downloads the newest matching SSU `.msu`, installs it with `wusa.exe /quiet /norestart`, and retries the next match on `0x800f0922`

### v2.9.0
- Added `DISM /AnalyzeComponentStore` parsing before component cleanup
- `StartComponentCleanup /ResetBase` now runs only when cleanup is recommended and reclaimable component-store data is at least 1024 MB

### v2.8.0
- Added optional `-StageSSU` / `-StageServicingStack` preflight before DISM
- Uses Windows Update Agent to find, download, and install the latest applicable Servicing Stack Update before `RestoreHealth`

### v2.7.0
- Added `-RepairDelivery` to reset Delivery Optimization cache and stale download-mode policy values
- Full repair now includes Delivery Optimization cache/policy reset

### v2.6.0
- Added `-RepairWaaS` to reset Update Orchestrator services and USO scheduled tasks
- Full repair now refreshes USO settings and re-enables disabled `\Microsoft\Windows\UpdateOrchestrator\*` tasks

### v2.5.0
- Added WSUS / SUP posture diagnostics for `WUServer`, `WUStatusServer`, target groups, `UseWUServer`, dual-scan, and policy-driven update source settings
- Added DNS resolution summaries and posture warnings for mismatched or incomplete WSUS policy state

### v2.4.0
- Added Microsoft Update Health Tools / Windows Remediation detection
- Added `uhssvc`, `sedsvc`, `sedlauncher`, remediation process, install path/version, and `rempl` task diagnostics

### v2.3.0
- Added WaaSMedic service/task/event diagnostics to the pre-check report
- Added Delivery Optimization peer cache health, active job count, peer count, cache size, and transfer byte totals

### v2.2.0
- Added ranked Windows Update HRESULT diagnostics from `%WINDIR%\WindowsUpdate.log` and converted ETW traces
- Added Microsoft reference links for the top recurring Windows Update error codes

### v2.1.0
- Diagnostic pre-check report with formatted status table (services, folders, DISM health, pending reboot, last update, recent errors)
- Selective repair via `-RepairServices`, `-RepairDLLs`, `-RepairStore`, `-RepairDISM`, `-RepairSFC`, `-RepairNetwork` switches
- Progress tracking with `Write-Progress` (Phase X of Y with percentage)
- Event log integration: writes start/completion summary to Application log under source "WURepair"
- Post-repair before/after comparison table
- Triggers Windows Update check after all repairs

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
