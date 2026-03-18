# CLAUDE.md - WURepair

## Overview
Comprehensive Windows Update component repair. Stops services, renames data stores, re-registers 37 DLLs, runs DISM/SFC, resets network stack, and more. v2.0.0.

## Tech Stack
- PowerShell 5.1, CLI/console (no GUI)

## Key Details
- ~1,262 lines, single-file
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

## Build/Run
```powershell
# Run as Administrator
.\WURepair.ps1
```

## Version
2.0.0
