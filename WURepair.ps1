<#
.SYNOPSIS
    WURepair - Comprehensive Windows Update Repair Tool
.DESCRIPTION
    Thoroughly diagnoses, repairs, and resets Windows Update components.
    Includes service management, cache clearing, component re-registration,
    DISM/SFC integration, network resets, hosts file cleanup, firewall repair,
    SSL/TLS configuration, and detailed logging.
.NOTES
    Author: Matt Parker
    Requires: Administrator privileges
    Version: 2.0.0
#>

#Requires -RunAsAdministrator

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    LogPath        = "$env:USERPROFILE\Desktop\WURepair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    BackupPath     = "$env:SystemRoot\WURepair_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    TempPath       = "$env:TEMP\WURepair"
    Verbose        = $true
    CreateBackup   = $true
    FullReset      = $true
}

# Windows Update related services - with correct start types
$Script:WUServices = @(
    @{ Name = 'wuauserv'; DisplayName = 'Windows Update'; StartType = 'Manual'; DelayedStart = $false },
    @{ Name = 'bits'; DisplayName = 'Background Intelligent Transfer Service'; StartType = 'Manual'; DelayedStart = $true },
    @{ Name = 'cryptsvc'; DisplayName = 'Cryptographic Services'; StartType = 'Automatic'; DelayedStart = $false },
    @{ Name = 'msiserver'; DisplayName = 'Windows Installer'; StartType = 'Manual'; DelayedStart = $false },
    @{ Name = 'TrustedInstaller'; DisplayName = 'Windows Modules Installer'; StartType = 'Manual'; DelayedStart = $false },
    @{ Name = 'appidsvc'; DisplayName = 'Application Identity'; StartType = 'Manual'; DelayedStart = $false },
    @{ Name = 'dosvc'; DisplayName = 'Delivery Optimization'; StartType = 'Automatic'; DelayedStart = $true }
)

# BITS dependencies
$Script:BITSDependencies = @('RpcSs', 'EventSystem', 'SystemEventsBroker')

# DLLs to re-register
$Script:WUDlls = @(
    'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll',
    'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll',
    'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll',
    'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
    'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll',
    'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll',
    'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll',
    'wuwebv.dll', 'wudriver.dll'
)

# Folders to clear/reset
$Script:WUFolders = @(
    "$env:SystemRoot\SoftwareDistribution",
    "$env:SystemRoot\System32\catroot2"
)

# Microsoft domains that should NOT be blocked
$Script:MicrosoftDomains = @(
    'update.microsoft.com',
    'windowsupdate.microsoft.com',
    'windowsupdate.com',
    'download.windowsupdate.com',
    'download.microsoft.com',
    'wustat.windows.com',
    'ntservicepack.microsoft.com',
    'go.microsoft.com',
    'dl.delivery.mp.microsoft.com',
    'download.delivery.mp.microsoft.com',
    'emdl.ws.microsoft.com',
    'statsfe2.update.microsoft.com',
    'statsfe2.ws.microsoft.com',
    'sls.update.microsoft.com',
    'fe2.update.microsoft.com',
    'fe3.delivery.mp.microsoft.com',
    'fe2.ws.microsoft.com',
    'ctldl.windowsupdate.com',
    'redir.metaservices.microsoft.com',
    'validation.sls.microsoft.com',
    'activation.sls.microsoft.com',
    'validation-v2.sls.microsoft.com',
    'displaycatalog.mp.microsoft.com',
    'licensing.mp.microsoft.com',
    'purchase.mp.microsoft.com',
    'displaycatalog.md.mp.microsoft.com',
    'settings-win.data.microsoft.com',
    'settings.data.microsoft.com'
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SECTION')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $colors = @{
        'INFO'    = 'Cyan'
        'SUCCESS' = 'Green'
        'WARNING' = 'Yellow'
        'ERROR'   = 'Red'
        'SECTION' = 'Magenta'
    }
    
    switch ($Level) {
        'SECTION' {
            Write-Host ""
            Write-Host ("=" * 70) -ForegroundColor $colors[$Level]
            Write-Host "  $Message" -ForegroundColor $colors[$Level]
            Write-Host ("=" * 70) -ForegroundColor $colors[$Level]
        }
        'SUCCESS' {
            Write-Host "[+] $Message" -ForegroundColor $colors[$Level]
        }
        'WARNING' {
            Write-Host "[!] $Message" -ForegroundColor $colors[$Level]
        }
        'ERROR' {
            Write-Host "[X] $Message" -ForegroundColor $colors[$Level]
        }
        default {
            Write-Host "    $Message" -ForegroundColor $colors[$Level]
        }
    }
    
    Add-Content -Path $Script:Config.LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Show-Banner {
    Clear-Host
    $banner = @"

    ╦ ╦╦ ╦  ╦═╗┌─┐┌─┐┌─┐┬┬─┐
    ║║║║ ║  ╠╦╝├┤ ├─┘├─┤│├┬┘
    ╚╩╝╚═╝  ╩╚═└─┘┴  ┴ ┴┴┴└─
    Windows Update Repair Tool v2.0
    ─────────────────────────────────

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ServiceStatus {
    param([string]$ServiceName)
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return @{
            Name = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartType = $service.StartType
        }
    }
    catch {
        return $null
    }
}

# ============================================================================
# NEW: HOSTS FILE REPAIR
# ============================================================================

function Repair-HostsFile {
    Write-Log "HOSTS FILE - Removing Microsoft Domain Blocks" -Level SECTION
    
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backupPath = "$env:SystemRoot\System32\drivers\etc\hosts.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    if (-not (Test-Path $hostsPath)) {
        Write-Log "Hosts file not found" -Level WARNING
        return
    }
    
    # Backup hosts file
    try {
        Copy-Item -Path $hostsPath -Destination $backupPath -Force -ErrorAction Stop
        Write-Log "Hosts file backed up to: $backupPath" -Level SUCCESS
    }
    catch {
        Write-Log "Could not backup hosts file: $($_.Exception.Message)" -Level WARNING
    }
    
    # Read current hosts file
    try {
        $hostsContent = Get-Content -Path $hostsPath -ErrorAction Stop
    }
    catch {
        Write-Log "Could not read hosts file" -Level ERROR
        return
    }
    
    $removedCount = 0
    $newContent = @()
    
    foreach ($line in $hostsContent) {
        $shouldRemove = $false
        
        # Check if line contains any Microsoft domain we need
        foreach ($domain in $Script:MicrosoftDomains) {
            if ($line -match [regex]::Escape($domain)) {
                # Check if it's a blocking entry (points to 0.0.0.0 or 127.0.0.1)
                if ($line -match '^\s*(0\.0\.0\.0|127\.0\.0\.1)\s+') {
                    $shouldRemove = $true
                    $removedCount++
                    Write-Log "Removing block: $line" -Level INFO
                    break
                }
            }
        }
        
        if (-not $shouldRemove) {
            $newContent += $line
        }
    }
    
    if ($removedCount -gt 0) {
        try {
            # Remove read-only attribute if present
            $file = Get-Item -Path $hostsPath -Force
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
            }
            
            Set-Content -Path $hostsPath -Value $newContent -Force -ErrorAction Stop
            Write-Log "Removed $removedCount Microsoft domain blocks from hosts file" -Level SUCCESS
        }
        catch {
            Write-Log "Could not write to hosts file: $($_.Exception.Message)" -Level ERROR
            Write-Log "You may need to manually edit: $hostsPath" -Level WARNING
        }
    }
    else {
        Write-Log "No Microsoft domain blocks found in hosts file" -Level SUCCESS
    }
}

# ============================================================================
# NEW: SSL/TLS CONFIGURATION REPAIR
# ============================================================================

function Repair-TLSConfiguration {
    Write-Log "SSL/TLS - Repairing Secure Connection Settings" -Level SECTION
    
    # Enable TLS 1.2 (required for Windows Update)
    $protocols = @(
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; Name = 'Enabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; Name = 'DisabledByDefault'; Value = 0 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; Name = 'Enabled'; Value = 1 },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; Name = 'DisabledByDefault'; Value = 0 }
    )
    
    foreach ($setting in $protocols) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type DWord -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
    Write-Log "TLS 1.2 enabled" -Level SUCCESS
    
    # Set .NET to use system default TLS
    $netPaths = @(
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    )
    
    foreach ($path in $netPaths) {
        try {
            if (Test-Path $path) {
                Set-ItemProperty -Path $path -Name 'SystemDefaultTlsVersions' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $path -Name 'SchUseStrongCrypto' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }
    Write-Log ".NET configured to use strong cryptography" -Level SUCCESS
    
    # Reset Internet Settings
    try {
        $inetPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
        Remove-ItemProperty -Path $inetPath -Name 'ProxyEnable' -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $inetPath -Name 'ProxyServer' -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $inetPath -Name 'ProxyOverride' -Force -ErrorAction SilentlyContinue
        Write-Log "Proxy settings cleared" -Level SUCCESS
    }
    catch { }
    
    # Force PowerShell to use TLS 1.2 for this session
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Log "PowerShell TLS 1.2 enforced" -Level SUCCESS
    }
    catch { }
}

# ============================================================================
# NEW: FIREWALL RULES REPAIR
# ============================================================================

function Repair-FirewallRules {
    Write-Log "FIREWALL - Ensuring Windows Update Traffic Allowed" -Level SECTION
    
    # Remove any rules blocking Windows Update
    try {
        $blockingRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
            ($_.DisplayName -match 'Windows Update|BITS|wuauserv|dosvc' -and $_.Action -eq 'Block') -or
            ($_.DisplayName -match 'Block.*Microsoft' -or $_.DisplayName -match 'Block.*Update')
        }
        
        foreach ($rule in $blockingRules) {
            try {
                Remove-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
                Write-Log "Removed blocking rule: $($rule.DisplayName)" -Level SUCCESS
            }
            catch { }
        }
    }
    catch {
        Write-Log "Could not query firewall rules" -Level WARNING
    }
    
    # Ensure Windows Update services are allowed
    $servicesToAllow = @(
        @{ Name = 'svchost.exe'; Path = "$env:SystemRoot\System32\svchost.exe" },
        @{ Name = 'wuauclt.exe'; Path = "$env:SystemRoot\System32\wuauclt.exe" },
        @{ Name = 'UsoClient.exe'; Path = "$env:SystemRoot\System32\UsoClient.exe" }
    )
    
    foreach ($svc in $servicesToAllow) {
        if (Test-Path $svc.Path) {
            try {
                # Check if allow rule exists
                $existingRule = Get-NetFirewallRule -DisplayName "Allow $($svc.Name) - WURepair" -ErrorAction SilentlyContinue
                if (-not $existingRule) {
                    New-NetFirewallRule -DisplayName "Allow $($svc.Name) - WURepair" `
                        -Direction Outbound `
                        -Program $svc.Path `
                        -Action Allow `
                        -Profile Any `
                        -ErrorAction SilentlyContinue | Out-Null
                }
            }
            catch { }
        }
    }
    Write-Log "Firewall rules configured for Windows Update" -Level SUCCESS
}

# ============================================================================
# NEW: SERVICE DEPENDENCY REPAIR
# ============================================================================

function Repair-ServiceDependencies {
    Write-Log "DEPENDENCIES - Repairing Service Dependencies" -Level SECTION
    
    # Ensure BITS dependencies are running
    foreach ($depName in $Script:BITSDependencies) {
        try {
            $dep = Get-Service -Name $depName -ErrorAction SilentlyContinue
            if ($dep) {
                # Ensure not disabled
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$depName"
                $startType = (Get-ItemProperty -Path $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
                if ($startType -eq 4) {
                    Set-ItemProperty -Path $regPath -Name 'Start' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Log "$depName was disabled, set to Automatic" -Level SUCCESS
                }
                
                if ($dep.Status -ne 'Running') {
                    Start-Service -Name $depName -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
            }
        }
        catch { }
    }
    
    # Fix BITS service configuration
    $bitsRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BITS"
    if (Test-Path $bitsRegPath) {
        try {
            # Reset BITS to default configuration
            Set-ItemProperty -Path $bitsRegPath -Name 'Start' -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $bitsRegPath -Name 'DelayedAutoStart' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            
            # Reset ImagePath if corrupted
            $defaultImagePath = '%SystemRoot%\System32\svchost.exe -k netsvcs -p'
            Set-ItemProperty -Path $bitsRegPath -Name 'ImagePath' -Value $defaultImagePath -Type ExpandString -Force -ErrorAction SilentlyContinue
            
            Write-Log "BITS service configuration repaired" -Level SUCCESS
        }
        catch {
            Write-Log "Could not repair BITS configuration" -Level WARNING
        }
    }
    
    # Fix Delivery Optimization service
    $dosvcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\dosvc"
    if (Test-Path $dosvcRegPath) {
        try {
            $currentStart = (Get-ItemProperty -Path $dosvcRegPath -Name 'Start' -ErrorAction SilentlyContinue).Start
            if ($currentStart -eq 4) {
                Set-ItemProperty -Path $dosvcRegPath -Name 'Start' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $dosvcRegPath -Name 'DelayedAutoStart' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Log "Delivery Optimization was DISABLED, now set to Automatic (Delayed)" -Level SUCCESS
            }
        }
        catch {
            Write-Log "Could not repair Delivery Optimization" -Level WARNING
        }
    }
}

# ============================================================================
# NEW: WINDOWS UPDATE POLICIES REPAIR
# ============================================================================

function Repair-UpdatePolicies {
    Write-Log "POLICIES - Removing Windows Update Restrictions" -Level SECTION
    
    # Registry paths that can block Windows Update
    $policiesToRemove = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DisableWindowsUpdateAccess' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DoNotConnectToWindowsUpdateInternetLocations' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'WUServer' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'WUStatusServer' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'UseWUServer' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoWindowsUpdate' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoWindowsUpdate' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'SetDisableUXWUAccess' }
    )
    
    $removedCount = 0
    foreach ($policy in $policiesToRemove) {
        try {
            if (Test-Path $policy.Path) {
                $value = Get-ItemProperty -Path $policy.Path -Name $policy.Name -ErrorAction SilentlyContinue
                if ($null -ne $value) {
                    Remove-ItemProperty -Path $policy.Path -Name $policy.Name -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed: $($policy.Name)" -Level SUCCESS
                    $removedCount++
                }
            }
        }
        catch { }
    }
    
    if ($removedCount -eq 0) {
        Write-Log "No blocking policies found" -Level SUCCESS
    }
    else {
        Write-Log "Removed $removedCount blocking policies" -Level SUCCESS
    }
    
    # Check for WSUS redirection (common in enterprise/LTSC)
    $wsusPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path $wsusPath) {
        $wuServer = (Get-ItemProperty -Path $wsusPath -Name 'WUServer' -ErrorAction SilentlyContinue).WUServer
        if ($wuServer) {
            Write-Log "WSUS Server configured: $wuServer" -Level WARNING
            Write-Log "If this is incorrect, updates will fail. Remove with Group Policy." -Level WARNING
        }
    }
}

# ============================================================================
# DIAGNOSTIC FUNCTIONS
# ============================================================================

function Get-WUDiagnostics {
    Write-Log "DIAGNOSTICS - Gathering System Information" -Level SECTION
    
    # OS Information
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    Write-Log "OS: $($os.Caption) ($($os.Version)) Build $($os.BuildNumber)"
    Write-Log "Architecture: $($os.OSArchitecture)"
    Write-Log "Install Date: $($os.InstallDate)"
    Write-Log "Last Boot: $($os.LastBootUpTime)"
    
    # Check for LTSC/LTSB (different update behavior)
    if ($os.Caption -match 'LTSC|LTSB|IoT') {
        Write-Log "LTSC/IoT Edition detected - limited feature updates available" -Level WARNING
    }
    
    # Disk Space
    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
    $freeGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($systemDrive.Size / 1GB, 2)
    Write-Log "System Drive: $freeGB GB free of $totalGB GB"
    
    if ($freeGB -lt 10) {
        Write-Log "Low disk space may cause Windows Update issues!" -Level WARNING
    }
    
    # Service Status
    Write-Log ""
    Write-Log "Windows Update Service Status:"
    foreach ($svc in $Script:WUServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
            $startType = (Get-ItemProperty -Path $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
            $startTypeName = switch ($startType) { 0 { 'Boot' } 1 { 'System' } 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } default { 'Unknown' } }
            
            if ($startType -eq 4) {
                Write-Log "  $($svc.DisplayName): $($service.Status) (DISABLED!)" -Level ERROR
            }
            else {
                Write-Log "  $($svc.DisplayName): $($service.Status) ($startTypeName)"
            }
        }
        else {
            Write-Log "  ${svc}: Not Found" -Level WARNING
        }
    }
    
    # Check for pending reboot
    $pendingReboot = $false
    $rebootPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    
    foreach ($path in $rebootPaths) {
        if (Test-Path $path) {
            $pendingReboot = $true
            break
        }
    }
    
    Write-Log ""
    if ($pendingReboot) {
        Write-Log "Pending reboot detected - may need to restart before updates work" -Level WARNING
    }
    else {
        Write-Log "No pending reboot detected" -Level SUCCESS
    }
    
    # Check Windows Update folder sizes
    Write-Log ""
    Write-Log "Windows Update Folder Sizes:"
    foreach ($folder in $Script:WUFolders) {
        if (Test-Path $folder) {
            $size = (Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            Write-Log "  $folder : $sizeMB MB"
        }
        else {
            Write-Log "  $folder : Not Found" -Level WARNING
        }
    }
    
    # Check for stuck pending.xml
    $pendingXml = "$env:SystemRoot\WinSxS\pending.xml"
    if (Test-Path $pendingXml) {
        Write-Log ""
        Write-Log "pending.xml exists - may indicate stuck updates" -Level WARNING
    }
    
    # Check hosts file for Microsoft blocks
    Write-Log ""
    Write-Log "Checking hosts file for Microsoft blocks..."
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hostsPath) {
        $hostsContent = Get-Content -Path $hostsPath -ErrorAction SilentlyContinue
        $blockedDomains = @()
        foreach ($line in $hostsContent) {
            foreach ($domain in $Script:MicrosoftDomains) {
                if ($line -match [regex]::Escape($domain) -and $line -match '^\s*(0\.0\.0\.0|127\.0\.0\.1)') {
                    $blockedDomains += $domain
                }
            }
        }
        if ($blockedDomains.Count -gt 0) {
            Write-Log "Found $($blockedDomains.Count) blocked Microsoft domains in hosts file!" -Level ERROR
        }
        else {
            Write-Log "No Microsoft blocks in hosts file" -Level SUCCESS
        }
    }
    
    return @{
        OSVersion = $os.Version
        Build = $os.BuildNumber
        FreeSpaceGB = $freeGB
        PendingReboot = $pendingReboot
        IsLTSC = ($os.Caption -match 'LTSC|LTSB|IoT')
    }
}

function Test-WindowsUpdateConnectivity {
    Write-Log "CONNECTIVITY - Testing Windows Update Servers" -Level SECTION
    
    # Force TLS 1.2 for these tests
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    $endpoints = @(
        @{ Name = "Windows Update"; URL = "https://update.microsoft.com" },
        @{ Name = "Microsoft Update"; URL = "https://www.update.microsoft.com" },
        @{ Name = "Download Center"; URL = "https://download.windowsupdate.com" },
        @{ Name = "Windows Update Catalog"; URL = "https://catalog.update.microsoft.com" },
        @{ Name = "Delivery Optimization"; URL = "https://download.delivery.mp.microsoft.com" }
    )
    
    $allSuccess = $true
    $failedCount = 0
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.URL -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            Write-Log "$($endpoint.Name): Reachable" -Level SUCCESS
        }
        catch {
            $errorMsg = $_.Exception.Message
            
            # Provide specific guidance based on error
            if ($errorMsg -match '403') {
                Write-Log "$($endpoint.Name): BLOCKED (403 Forbidden) - Check hosts file/firewall" -Level ERROR
            }
            elseif ($errorMsg -match 'SSL|TLS|secure channel') {
                Write-Log "$($endpoint.Name): SSL/TLS ERROR - Protocol may be disabled" -Level ERROR
            }
            elseif ($errorMsg -match 'resolve') {
                Write-Log "$($endpoint.Name): DNS FAILURE - Check hosts file or DNS settings" -Level ERROR
            }
            else {
                Write-Log "$($endpoint.Name): UNREACHABLE - $errorMsg" -Level ERROR
            }
            
            $allSuccess = $false
            $failedCount++
        }
    }
    
    if ($failedCount -gt 0) {
        Write-Log ""
        Write-Log "Connectivity issues detected! This script will attempt to fix them." -Level WARNING
    }
    
    return $allSuccess
}

# ============================================================================
# REPAIR FUNCTIONS
# ============================================================================

function Stop-WUServices {
    Write-Log "SERVICES - Stopping Windows Update Services" -Level SECTION
    
    $stopOrder = @('wuauserv', 'bits', 'dosvc', 'cryptsvc', 'msiserver')
    
    foreach ($svcName in $stopOrder) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') {
                Write-Log "Stopping $($svc.DisplayName)..."
                try {
                    Stop-Service -Name $svcName -Force -ErrorAction Stop
                    $timeout = 30
                    $timer = [Diagnostics.Stopwatch]::StartNew()
                    while ((Get-Service -Name $svcName).Status -ne 'Stopped' -and $timer.Elapsed.TotalSeconds -lt $timeout) {
                        Start-Sleep -Milliseconds 500
                    }
                    
                    if ((Get-Service -Name $svcName).Status -eq 'Stopped') {
                        Write-Log "$($svc.DisplayName) stopped" -Level SUCCESS
                    }
                    else {
                        Write-Log "$($svc.DisplayName) did not stop within timeout" -Level WARNING
                    }
                }
                catch {
                    Write-Log "Failed to stop $($svc.DisplayName): $($_.Exception.Message)" -Level WARNING
                }
            }
            else {
                Write-Log "$($svc.DisplayName) already stopped"
            }
        }
    }
}

function Start-WUServices {
    Write-Log "SERVICES - Starting Windows Update Services" -Level SECTION
    
    $startOrder = @('cryptsvc', 'bits', 'wuauserv', 'dosvc', 'msiserver')
    
    foreach ($svcName in $startOrder) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            # Ensure service is not disabled
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
            $startType = (Get-ItemProperty -Path $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
            
            if ($startType -eq 4) {
                # Service is disabled, enable it first
                Set-ItemProperty -Path $regPath -Name 'Start' -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Log "$svcName was disabled, now enabled" -Level SUCCESS
            }
            
            if ($svc.Status -ne 'Running') {
                Write-Log "Starting $($svc.DisplayName)..."
                try {
                    Start-Service -Name $svcName -ErrorAction Stop
                    Write-Log "$($svc.DisplayName) started" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to start $($svc.DisplayName): $($_.Exception.Message)" -Level WARNING
                    
                    # If BITS fails, try repairing it
                    if ($svcName -eq 'bits') {
                        Write-Log "Attempting BITS repair..." -Level INFO
                        try {
                            # Re-register BITS
                            $null = regsvr32 /s "$env:SystemRoot\System32\qmgr.dll" 2>&1
                            $null = regsvr32 /s "$env:SystemRoot\System32\qmgrprxy.dll" 2>&1
                            Start-Sleep -Seconds 2
                            Start-Service -Name 'bits' -ErrorAction SilentlyContinue
                        }
                        catch { }
                    }
                }
            }
            else {
                Write-Log "$($svc.DisplayName) already running" -Level SUCCESS
            }
        }
    }
}

function Reset-WUServiceConfig {
    Write-Log "SERVICES - Resetting Service Configurations" -Level SECTION
    
    foreach ($svc in $Script:WUServices) {
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
            
            if (Test-Path $regPath) {
                # Set correct start type
                $startValue = switch ($svc.StartType) {
                    'Automatic' { 2 }
                    'Manual' { 3 }
                    default { 3 }
                }
                
                Set-ItemProperty -Path $regPath -Name 'Start' -Value $startValue -Type DWord -Force -ErrorAction SilentlyContinue
                
                # Set delayed start if needed
                if ($svc.DelayedStart) {
                    Set-ItemProperty -Path $regPath -Name 'DelayedAutoStart' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }
                
                Write-Log "$($svc.Name): StartType set to $($svc.StartType)" -Level SUCCESS
            }
        }
        catch {
            Write-Log "Failed to configure $($svc.Name): $($_.Exception.Message)" -Level WARNING
        }
    }
    
    # Reset BITS jobs
    Write-Log "Clearing BITS transfer queue..."
    try {
        Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue
        Write-Log "BITS queue cleared" -Level SUCCESS
    }
    catch {
        Write-Log "Could not clear BITS queue (may be empty)" -Level WARNING
    }
}

function Backup-WUFolders {
    Write-Log "BACKUP - Creating Backup of Windows Update Folders" -Level SECTION
    
    if (-not (Test-Path $Script:Config.BackupPath)) {
        New-Item -Path $Script:Config.BackupPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
    
    foreach ($folder in $Script:WUFolders) {
        if (Test-Path $folder) {
            $folderName = Split-Path $folder -Leaf
            
            Write-Log "Backing up $folderName..."
            try {
                $backupName = "$folder.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                Rename-Item -Path $folder -NewName $backupName -Force -ErrorAction Stop
                Write-Log "$folderName backed up to $backupName" -Level SUCCESS
            }
            catch {
                Write-Log "Could not backup $folderName : $($_.Exception.Message)" -Level WARNING
            }
        }
    }
}

function Clear-WUCache {
    Write-Log "CACHE - Clearing Windows Update Cache" -Level SECTION
    
    foreach ($folder in $Script:WUFolders) {
        if (Test-Path $folder) {
            Write-Log "Clearing $folder..."
            try {
                Remove-Item -Path "$folder\*" -Recurse -Force -ErrorAction Stop
                Write-Log "$folder cleared" -Level SUCCESS
            }
            catch {
                Write-Log "Could not fully clear $folder (files may be in use)" -Level WARNING
                Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | 
                    ForEach-Object {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
            }
        }
        else {
            New-Item -Path $folder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Log "$folder recreated" -Level SUCCESS
        }
    }
    
    # Clear download cache
    $downloadCache = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $downloadCache) {
        Write-Log "Clearing download cache..."
        Remove-Item -Path "$downloadCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Clear pending.xml if exists
    $pendingXml = "$env:SystemRoot\WinSxS\pending.xml"
    if (Test-Path $pendingXml) {
        Write-Log "Removing stuck pending.xml..."
        try {
            takeown /f $pendingXml /a 2>&1 | Out-Null
            icacls $pendingXml /grant Administrators:F 2>&1 | Out-Null
            Remove-Item -Path $pendingXml -Force -ErrorAction Stop
            Write-Log "pending.xml removed" -Level SUCCESS
        }
        catch {
            Write-Log "Could not remove pending.xml (may require Safe Mode)" -Level WARNING
        }
    }
}

function Register-WUDlls {
    Write-Log "DLLS - Re-registering Windows Update DLLs" -Level SECTION
    
    $registered = 0
    $failed = 0
    
    foreach ($dll in $Script:WUDlls) {
        $dllPath = "$env:SystemRoot\System32\$dll"
        if (Test-Path $dllPath) {
            $result = regsvr32.exe /s $dllPath 2>&1
            $registered++
        }
        else {
            $dllPath = "$env:SystemRoot\SysWOW64\$dll"
            if (Test-Path $dllPath) {
                $result = regsvr32.exe /s $dllPath 2>&1
                $registered++
            }
            else {
                $failed++
            }
        }
    }
    
    Write-Log "$registered DLLs registered, $failed not found (normal for some)" -Level SUCCESS
}

function Reset-WinsockCatalog {
    Write-Log "NETWORK - Resetting Network Components" -Level SECTION
    
    Write-Log "Resetting Winsock catalog..."
    $result = netsh winsock reset 2>&1
    Write-Log "Winsock reset complete" -Level SUCCESS
    
    Write-Log "Resetting TCP/IP stack..."
    $result = netsh int ip reset 2>&1
    Write-Log "TCP/IP reset complete" -Level SUCCESS
    
    Write-Log "Flushing DNS cache..."
    $result = ipconfig /flushdns 2>&1
    Write-Log "DNS cache flushed" -Level SUCCESS
    
    Write-Log "Resetting proxy settings..."
    $result = netsh winhttp reset proxy 2>&1
    Write-Log "Proxy settings reset" -Level SUCCESS
}

function Reset-WURegistry {
    Write-Log "REGISTRY - Resetting Windows Update Registry Keys" -Level SECTION
    
    $keysToRemove = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
    )
    
    foreach ($key in $keysToRemove) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Force -Recurse -ErrorAction Stop
                Write-Log "Removed: $key" -Level SUCCESS
            }
            catch {
                Write-Log "Could not remove: $key" -Level WARNING
            }
        }
    }
    
    # Ensure Windows Update registry settings are correct
    $wuRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    if (-not (Test-Path $wuRegPath)) {
        New-Item -Path $wuRegPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    
    $auPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'
    if (-not (Test-Path $auPath)) {
        New-Item -Path $auPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    
    Write-Log "Registry cleanup complete" -Level SUCCESS
}

function Reset-WindowsUpdateAgent {
    Write-Log "AGENT - Resetting Windows Update Agent" -Level SECTION
    
    # Delete qmgr*.dat files
    Write-Log "Removing BITS data files..."
    $bitsLocations = @(
        "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader",
        "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"
    )
    
    foreach ($loc in $bitsLocations) {
        if (Test-Path $loc) {
            Get-ChildItem -Path $loc -Filter "qmgr*.dat" -ErrorAction SilentlyContinue | 
                ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Log "BITS data files removed" -Level SUCCESS
    
    Write-Log "Resetting Windows Update authorization..."
    $susClientId = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    if (Test-Path $susClientId) {
        Remove-ItemProperty -Path $susClientId -Name 'SusClientId' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $susClientId -Name 'SusClientIdValidation' -ErrorAction SilentlyContinue
    }
    Write-Log "Authorization reset complete" -Level SUCCESS
}

function Update-GroupPolicy {
    Write-Log "POLICY - Refreshing Group Policy" -Level SECTION
    
    Write-Log "Forcing Group Policy update..."
    $result = gpupdate /force 2>&1
    Write-Log "Group Policy refreshed" -Level SUCCESS
}

function Invoke-DISM {
    Write-Log "DISM - Running System Image Repairs" -Level SECTION
    
    Write-Log "Checking component store health..."
    $result = DISM /Online /Cleanup-Image /CheckHealth 2>&1
    Write-Log "Health check complete"
    
    Write-Log "Scanning component store (this may take several minutes)..."
    $result = DISM /Online /Cleanup-Image /ScanHealth 2>&1
    $scanOutput = $result -join "`n"
    
    if ($scanOutput -match "component store is repairable") {
        Write-Log "Component store corruption detected, repairing..." -Level WARNING
        
        Write-Log "Running RestoreHealth (this may take 15-30 minutes)..."
        $result = DISM /Online /Cleanup-Image /RestoreHealth 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Component store repaired successfully" -Level SUCCESS
        }
        else {
            Write-Log "RestoreHealth completed with issues - may need Windows media" -Level WARNING
        }
    }
    elseif ($scanOutput -match "No component store corruption detected") {
        Write-Log "No component store corruption detected" -Level SUCCESS
    }
    else {
        Write-Log "Scan completed"
    }
    
    Write-Log "Cleaning up superseded components..."
    $result = DISM /Online /Cleanup-Image /StartComponentCleanup 2>&1
    Write-Log "Component cleanup complete" -Level SUCCESS
}

function Invoke-SFC {
    Write-Log "SFC - Running System File Checker" -Level SECTION
    
    Write-Log "Scanning system files (this may take 10-15 minutes)..."
    
    $sfcOutput = sfc /scannow 2>&1
    $sfcResult = $sfcOutput -join "`n"
    
    if ($sfcResult -match "did not find any integrity violations") {
        Write-Log "No integrity violations found" -Level SUCCESS
    }
    elseif ($sfcResult -match "successfully repaired") {
        Write-Log "Corrupted files were found and repaired" -Level SUCCESS
    }
    elseif ($sfcResult -match "found corrupt files but was unable to fix") {
        Write-Log "Corrupt files found but could not be repaired" -Level WARNING
        Write-Log "Try running DISM again, then SFC" -Level WARNING
    }
    else {
        Write-Log "SFC scan completed"
    }
    
    $cbsLog = "$env:SystemRoot\Logs\CBS\CBS.log"
    if (Test-Path $cbsLog) {
        Write-Log "Detailed results in: $cbsLog"
    }
}

function Invoke-WindowsUpdateCheck {
    Write-Log "CHECK - Initiating Windows Update Check" -Level SECTION
    
    Write-Log "Triggering Windows Update scan..."
    try {
        $result = Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-Log "Update scan initiated via UsoClient" -Level SUCCESS
    }
    catch {
        try {
            $result = wuauclt.exe /detectnow /updatenow 2>&1
            Write-Log "Update scan initiated via wuauclt" -Level SUCCESS
        }
        catch {
            Write-Log "Could not trigger update scan automatically" -Level WARNING
        }
    }
    
    Write-Log "Open Windows Update settings to check for updates manually"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-WURepair {
    param(
        [switch]$SkipDISM,
        [switch]$SkipSFC,
        [switch]$SkipBackup,
        [switch]$QuickMode
    )
    
    Show-Banner
    
    if (-not (Test-AdminRights)) {
        Write-Log "This script requires Administrator privileges!" -Level ERROR
        Write-Log "Please right-click and 'Run as Administrator'"
        return
    }
    
    $startTime = Get-Date
    Write-Log "WURepair started at $startTime"
    Write-Log "Log file: $($Script:Config.LogPath)"
    
    # Create restore point
    Write-Log ""
    Write-Log "Creating system restore point..."
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WURepair - Before Windows Update Reset" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "Restore point created" -Level SUCCESS
    }
    catch {
        Write-Log "Could not create restore point (may be disabled)" -Level WARNING
    }
    
    # Run diagnostics
    $diag = Get-WUDiagnostics
    
    # Test connectivity
    $connectivity = Test-WindowsUpdateConnectivity
    
    # Confirm before proceeding
    Write-Host ""
    Write-Host "Ready to perform Windows Update reset." -ForegroundColor Yellow
    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  - Clean hosts file of Microsoft blocks" -ForegroundColor White
    Write-Host "  - Repair SSL/TLS configuration" -ForegroundColor White
    Write-Host "  - Fix firewall rules for Windows Update" -ForegroundColor White
    Write-Host "  - Repair service dependencies (BITS, Delivery Optimization)" -ForegroundColor White
    Write-Host "  - Remove Windows Update blocking policies" -ForegroundColor White
    Write-Host "  - Stop Windows Update services" -ForegroundColor White
    Write-Host "  - Clear update cache and temporary files" -ForegroundColor White
    Write-Host "  - Re-register system DLLs" -ForegroundColor White
    Write-Host "  - Reset network components" -ForegroundColor White
    Write-Host "  - Clean up registry entries" -ForegroundColor White
    if (-not $SkipDISM -and -not $QuickMode) {
        Write-Host "  - Run DISM repairs (can take 15-30 minutes)" -ForegroundColor White
    }
    if (-not $SkipSFC -and -not $QuickMode) {
        Write-Host "  - Run System File Checker" -ForegroundColor White
    }
    Write-Host ""
    
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Log "Operation cancelled by user" -Level WARNING
        return
    }
    
    # === NEW REPAIR STEPS ===
    Repair-HostsFile
    Repair-TLSConfiguration
    Repair-FirewallRules
    Repair-ServiceDependencies
    Repair-UpdatePolicies
    
    # === EXISTING REPAIR STEPS ===
    Stop-WUServices
    
    if (-not $SkipBackup -and $Script:Config.CreateBackup) {
        Backup-WUFolders
    }
    
    Clear-WUCache
    Reset-WUServiceConfig
    Register-WUDlls
    Reset-WinsockCatalog
    Reset-WURegistry
    Reset-WindowsUpdateAgent
    
    if (-not $SkipDISM -and -not $QuickMode) {
        Invoke-DISM
    }
    
    if (-not $SkipSFC -and -not $QuickMode) {
        Invoke-SFC
    }
    
    Start-WUServices
    Update-GroupPolicy
    
    # Test connectivity again
    Write-Log "POST-REPAIR CONNECTIVITY TEST" -Level SECTION
    $postConnectivity = Test-WindowsUpdateConnectivity
    
    Invoke-WindowsUpdateCheck
    
    # Summary
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Log "COMPLETE - Windows Update Repair Finished" -Level SECTION
    Write-Log "Duration: $([math]::Round($duration.TotalMinutes, 1)) minutes"
    Write-Log "Log saved to: $($Script:Config.LogPath)"
    
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Green
    Write-Host "                      REPAIR COMPLETE                               " -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  A system RESTART is REQUIRED to complete all repairs." -ForegroundColor Yellow
    Write-Host "  After restart, check for Windows Updates in Settings." -ForegroundColor White
    Write-Host ""
    
    if (-not $postConnectivity) {
        Write-Host "  NOTE: Connectivity issues may persist. After restart:" -ForegroundColor Yellow
        Write-Host "  - Check if third-party antivirus is blocking connections" -ForegroundColor White
        Write-Host "  - Verify no VPN is interfering" -ForegroundColor White
        Write-Host "  - Check corporate proxy/firewall settings" -ForegroundColor White
        Write-Host ""
    }
    
    if ($diag.IsLTSC) {
        Write-Host "  LTSC EDITION NOTE:" -ForegroundColor Cyan
        Write-Host "  Your Windows edition only receives security updates." -ForegroundColor White
        Write-Host "  Feature updates are not available for LTSC/IoT editions." -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "====================================================================" -ForegroundColor Green
    Write-Host ""
    
    $restart = Read-Host "Restart now? (Y/N)"
    if ($restart -match '^[Yy]') {
        Write-Log "Initiating restart..."
        Restart-Computer -Force
    }
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

$params = @{}

if ($args -contains '-SkipDISM') { $params['SkipDISM'] = $true }
if ($args -contains '-SkipSFC') { $params['SkipSFC'] = $true }
if ($args -contains '-SkipBackup') { $params['SkipBackup'] = $true }
if ($args -contains '-QuickMode' -or $args -contains '-Quick') { $params['QuickMode'] = $true }

if ($args -contains '-Help' -or $args -contains '-?') {
    Write-Host ""
    Write-Host "WURepair - Windows Update Repair Tool v2.0"
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host "    .\WURepair.ps1 [options]"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "    -Quick          Skip DISM and SFC scans (faster but less thorough)"
    Write-Host "    -QuickMode      Same as -Quick"
    Write-Host "    -SkipDISM       Skip DISM component store repair"
    Write-Host "    -SkipSFC        Skip System File Checker"
    Write-Host "    -SkipBackup     Skip backup of Windows Update folders"
    Write-Host "    -Help           Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:"
    Write-Host "    .\WURepair.ps1                    Full repair (recommended)"
    Write-Host "    .\WURepair.ps1 -Quick             Quick repair without DISM/SFC"
    Write-Host "    .\WURepair.ps1 -SkipDISM          Skip only DISM repair"
    Write-Host ""
    Write-Host "NEW IN v2.0:"
    Write-Host "    - Hosts file cleanup (removes Microsoft domain blocks)"
    Write-Host "    - SSL/TLS configuration repair"
    Write-Host "    - Firewall rules repair for Windows Update"
    Write-Host "    - Service dependency repair (fixes BITS/Delivery Optimization)"
    Write-Host "    - Windows Update policy removal"
    Write-Host "    - Post-repair connectivity test"
    Write-Host "    - LTSC/IoT edition detection"
    Write-Host ""
    exit
}

# Run the repair
Start-WURepair @params