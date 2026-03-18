# CLAUDE.md - WURepair

## Overview
Comprehensive Windows Update component repair. Stops services, renames data stores, re-registers 37 DLLs, runs DISM/SFC, resets network stack, and more. v2.1.0.

## Tech Stack
- PowerShell 5.1, CLI/console (no GUI)

## Key Details
- ~1,450 lines, single-file
- Diagnostic pre-check report: formatted status table showing service states, folder sizes, DISM health, pending reboot, last update, and last 5 WU errors from event log
- Selective repair via `-RepairServices`, `-RepairDLLs`, `-RepairStore`, `-RepairDISM`, `-RepairSFC`, `-RepairNetwork` switches (or `-RepairAll` / default = all)
- Progress tracking: `Write-Progress` bar with "Phase X of Y: Description"
- Event log integration: writes summary to Application log under source "WURepair" (EventId 1000=start, 1001=complete)
- Post-repair verification: re-runs diagnostic check and shows before/after comparison table
- Stops WU services, renames SoftwareDistribution + catroot2
- Re-registers 37 Windows Update DLLs via regsvr32
- Resets BITS and WU service permissions
- Repairs service registry entries
- DISM: CheckHealth, ScanHealth, RestoreHealth
- SFC /scannow
- Network stack reset (winsock + IP)
- Hosts file cleanup (removes WU-blocking entries)
- Firewall repair (re-enables profiles)
- SSL/TLS registry configuration
- Backs up registry before modifications
- Logs to Desktop (`WURepair_*.log`)
- Backups to `%SystemRoot%\WURepair_Backup_*`
- Triggers Windows Update check after repairs

## Build/Run
```powershell
# Run as Administrator - full repair
.\WURepair.ps1

# Selective repair
.\WURepair.ps1 -RepairServices
.\WURepair.ps1 -RepairStore -RepairDLLs
```

## Gotchas
- Banner uses box-drawing characters (not emoji) - safe for PowerShell encoding
- Event log source creation requires admin (handled by #Requires -RunAsAdministrator)
- DISM/SFC phases can take 15-30 minutes; use `-Quick` to skip

## Version History
- 2.1.0: Diagnostic pre-check, selective repair switches, progress tracking, event log integration, post-repair before/after comparison
- 2.0.0: Hosts file cleanup, SSL/TLS repair, firewall rules, service dependencies, policy removal, connectivity testing, LTSC detection
- 1.0.0: Initial release

## Version
2.1.0
