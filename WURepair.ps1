<#
.SYNOPSIS
    WURepair - Comprehensive Windows Update Repair Tool
.DESCRIPTION
    Thoroughly diagnoses, repairs, and resets Windows Update components.
    Includes service management, cache clearing, component re-registration,
    DISM/SFC integration, network resets, hosts file cleanup, firewall repair,
    SSL/TLS configuration, and detailed logging.

    v2.1.0 adds diagnostic pre-check report, selective repair via parameters,
    progress tracking, event log integration, and post-repair verification
    with before/after comparison.
.NOTES
    Author: Matt Parker
    Requires: Administrator privileges
    Version: 2.1.0
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
    Version        = '2.1.0'
    EventSource    = 'WURepair'
    Ui             = @{
        AccentColor   = 'Cyan'
        TitleColor    = 'White'
        MutedColor    = 'DarkGray'
        InfoColor     = 'Gray'
        SuccessColor  = 'Green'
        WarningColor  = 'Yellow'
        ErrorColor    = 'Red'
        SectionColor  = 'Magenta'
        EmphasisColor = 'DarkCyan'
    }
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

function Get-UiWidth {
    try {
        $width = [Console]::WindowWidth
    }
    catch {
        $width = 100
    }

    if ($width -lt 84) { return 84 }
    if ($width -gt 118) { return 118 }
    return $width
}

function Get-UiColor {
    param(
        [ValidateSet('Accent', 'Title', 'Muted', 'Info', 'Success', 'Warning', 'Error', 'Section', 'Emphasis')]
        [string]$Tone = 'Info'
    )

    switch ($Tone) {
        'Accent' { return $Script:Config.Ui.AccentColor }
        'Title' { return $Script:Config.Ui.TitleColor }
        'Muted' { return $Script:Config.Ui.MutedColor }
        'Success' { return $Script:Config.Ui.SuccessColor }
        'Warning' { return $Script:Config.Ui.WarningColor }
        'Error' { return $Script:Config.Ui.ErrorColor }
        'Section' { return $Script:Config.Ui.SectionColor }
        'Emphasis' { return $Script:Config.Ui.EmphasisColor }
        default { return $Script:Config.Ui.InfoColor }
    }
}

function Format-UiCell {
    param(
        [AllowNull()][string]$Text,
        [int]$Width
    )

    if ($Width -lt 1) {
        return ''
    }

    $safeText = if ($null -eq $Text) { '' } else { [string]$Text }
    $safeText = $safeText -replace '\s+', ' '

    if ($safeText.Length -gt $Width) {
        if ($Width -le 2) {
            return $safeText.Substring(0, $Width)
        }
        return $safeText.Substring(0, $Width - 1) + '...'
    }

    return $safeText.PadRight($Width)
}

function Get-StatusTone {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'Info'
    }

    if ($Value -match 'Disabled|Not Found|BLOCKED|UNREACHABLE|DNS FAILURE|SSL/TLS ERROR|Corrupted|Unable|Failed') {
        return 'Error'
    }

    if ($Value -match 'Stopped|Repairable|Pending|Required|Unknown|Skipped|Limited|Caution|Warning|Yes|block\(s\) found|blocked') {
        return 'Warning'
    }

    if ($Value -match 'Reachable|Healthy|Running|Enabled|No recent|No pending|No Microsoft blocks|^No$|Ready|Available|Created|Saved|Complete|Successful|Clean|Not present') {
        return 'Success'
    }

    return 'Info'
}

function Write-UiRule {
    param(
        [string]$Tone = 'Muted',
        [string]$Character = '─',
        [int]$Indent = 2,
        [int]$Width = 0
    )

    if ($Width -le 0) {
        $Width = [Math]::Min(80, (Get-UiWidth) - ($Indent + 2))
    }

    Write-Host ((' ' * $Indent) + ($Character * $Width)) -ForegroundColor (Get-UiColor $Tone)
}

function Write-UiHeader {
    param(
        [string]$Title,
        [string]$Subtitle = '',
        [string]$Tone = 'Section'
    )

    Write-Host ''
    Write-UiRule -Tone $Tone -Character '═'
    Write-Host ("  {0}" -f $Title) -ForegroundColor (Get-UiColor 'Title')
    if ($Subtitle) {
        Write-Host ("  {0}" -f $Subtitle) -ForegroundColor (Get-UiColor 'Info')
    }
    Write-UiRule -Tone $Tone
}

function Write-UiSubheading {
    param([string]$Title)

    Write-Host ''
    Write-Host ("  {0}" -f $Title) -ForegroundColor (Get-UiColor 'Title')
    Write-UiRule -Tone 'Muted' -Width ([Math]::Min(36, [Math]::Max(16, $Title.Length + 6)))
}

function Write-UiMetric {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Tone = 'Info',
        [int]$LabelWidth = 28
    )

    $safeWidth = [Math]::Max(16, $LabelWidth)
    Write-Host ("  {0}" -f (Format-UiCell -Text $Label -Width $safeWidth)) -ForegroundColor (Get-UiColor 'Muted') -NoNewline
    Write-Host '  ' -NoNewline
    Write-Host $Value -ForegroundColor (Get-UiColor $Tone)
}

function Write-UiComparisonLine {
    param(
        [string]$Label,
        [string]$Before,
        [string]$After,
        [string]$Tone = 'Info',
        [int]$LabelWidth = 28,
        [int]$BeforeWidth = 26
    )

    Write-Host ("  {0}" -f (Format-UiCell -Text $Label -Width $LabelWidth)) -ForegroundColor (Get-UiColor 'Muted') -NoNewline
    Write-Host '  ' -NoNewline
    Write-Host (Format-UiCell -Text $Before -Width $BeforeWidth) -ForegroundColor (Get-UiColor 'Info') -NoNewline
    Write-Host '  ->  ' -ForegroundColor (Get-UiColor 'Muted') -NoNewline
    Write-Host $After -ForegroundColor (Get-UiColor $Tone)
}

function Write-UiList {
    param(
        [string]$Title,
        [string[]]$Items,
        [string]$Tone = 'Info'
    )

    if ($Title) {
        Write-UiSubheading -Title $Title
    }

    foreach ($item in $Items) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            Write-Host ("  • {0}" -f $item) -ForegroundColor (Get-UiColor $Tone)
        }
    }
}

function Write-UiCallout {
    param(
        [string]$Title,
        [string[]]$Lines,
        [string]$Tone = 'Info'
    )

    Write-Host ''
    Write-Host ("  [{0}] {1}" -f $Tone.ToUpper(), $Title) -ForegroundColor (Get-UiColor $Tone)
    foreach ($line in $Lines) {
        Write-Host ("    {0}" -f $line) -ForegroundColor (Get-UiColor 'Info')
    }
}

function Read-Confirmation {
    param(
        [string]$Prompt,
        [switch]$DefaultYes
    )

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $response = Read-Host "$Prompt $suffix"
        if ($null -eq $response) {
            $response = ''
        }
        $response = $response.Trim()

        if ([string]::IsNullOrWhiteSpace($response)) {
            return [bool]$DefaultYes
        }

        switch -Regex ($response) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default {
                Write-Log "Please enter Y or N." -Level WARNING
            }
        }
    }
}

function Get-EstimatedRepairDuration {
    param(
        [bool]$SelectiveMode,
        [bool]$RepairDISM,
        [bool]$RepairSFC,
        [bool]$RepairNetwork,
        [bool]$RepairStore
    )

    $minMinutes = if ($SelectiveMode) { 4 } else { 10 }
    $maxMinutes = if ($SelectiveMode) { 12 } else { 22 }

    if ($RepairStore) {
        $minMinutes += 2
        $maxMinutes += 5
    }
    if ($RepairNetwork) {
        $minMinutes += 1
        $maxMinutes += 3
    }
    if ($RepairDISM) {
        $minMinutes += 15
        $maxMinutes += 30
    }
    if ($RepairSFC) {
        $minMinutes += 8
        $maxMinutes += 15
    }

    return "$minMinutes-$maxMinutes minutes"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'SECTION')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'SECTION' {
            Write-UiHeader -Title $Message -Tone 'Section'
        }
        'SUCCESS' {
            Write-Host ("  [OK] {0}" -f $Message) -ForegroundColor (Get-UiColor 'Success')
        }
        'WARNING' {
            Write-Host ("  [!]  {0}" -f $Message) -ForegroundColor (Get-UiColor 'Warning')
        }
        'ERROR' {
            Write-Host ("  [X]  {0}" -f $Message) -ForegroundColor (Get-UiColor 'Error')
        }
        default {
            if ([string]::IsNullOrWhiteSpace($Message)) {
                Write-Host ''
            }
            else {
                Write-Host ("  • {0}" -f $Message) -ForegroundColor (Get-UiColor 'Info')
            }
        }
    }

    Add-Content -Path $Script:Config.LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-UiRule -Tone 'Emphasis' -Character '═'
    Write-Host ("  WURepair  v{0}" -f $Script:Config.Version) -ForegroundColor (Get-UiColor 'Accent')
    Write-Host '  Repair Windows Update with guided diagnostics, safer defaults, and clearer next steps.' -ForegroundColor (Get-UiColor 'Title')
    Write-Host '  Best used when updates are blocked by debloaters, policy drift, service damage, or cache corruption.' -ForegroundColor (Get-UiColor 'Info')
    Write-UiRule -Tone 'Emphasis'
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
# EVENT LOG INTEGRATION
# ============================================================================

function Initialize-EventSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Script:Config.EventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($Script:Config.EventSource, 'Application')
        }
    }
    catch {
        # Source creation may fail if already registered to another log; ignore
    }
}

function Write-RepairEventLog {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = [System.Diagnostics.EventLogEntryType]::Information,
        [int]$EventId = 1000
    )
    try {
        Write-EventLog -LogName 'Application' -Source $Script:Config.EventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction SilentlyContinue
    }
    catch { }
}

# ============================================================================
# DIAGNOSTIC PRE-CHECK REPORT
# ============================================================================

function Get-DiagnosticReport {
    <#
    .SYNOPSIS
        Collects comprehensive health check data and returns a hashtable snapshot.
        Displayed as a compact preflight snapshot.
    #>
    Write-Log "DIAGNOSTIC HEALTH CHECK" -Level SECTION

    $report = @{}

    # -- System overview --
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $report['Edition'] = $os.Caption
        $report['OSSummary'] = "$($os.Caption) | Version $($os.Version) | Build $($os.BuildNumber)"
        $report['IsLTSC'] = ($os.Caption -match 'LTSC|LTSB|IoT')
    }
    else {
        $report['Edition'] = 'Unable to determine'
        $report['OSSummary'] = 'Unable to read operating system details'
        $report['IsLTSC'] = $false
    }

    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
    if ($systemDrive) {
        $freeGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $report['FreeSpaceGB'] = $freeGB
        $report['SystemDrive'] = "$freeGB GB free of $totalGB GB"
    }
    else {
        $report['FreeSpaceGB'] = $null
        $report['SystemDrive'] = 'Unable to read disk space'
    }

    # -- Service statuses --
    $coreServices = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    $serviceResults = @()
    foreach ($svcName in $coreServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
            $startVal = (Get-ItemProperty -Path $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
            $startLabel = switch ($startVal) { 0 { 'Boot' } 1 { 'System' } 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } default { 'Unknown' } }
            $statusLabel = "$($svc.Status) ($startLabel)"
        } else {
            $statusLabel = 'Not Found'
        }
        $serviceResults += [PSCustomObject]@{ Component = $svc.DisplayName; Status = $statusLabel }
    }
    $report['Services'] = $serviceResults

    # -- SoftwareDistribution folder --
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) {
        $sdSize = (Get-ChildItem -Path $sdPath -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
        $sdSizeMB = [math]::Round($sdSize / 1MB, 2)
        $sdLastMod = (Get-Item $sdPath -Force -ErrorAction SilentlyContinue).LastWriteTime
        $report['SoftwareDistribution'] = "$sdSizeMB MB | Modified: $($sdLastMod.ToString('yyyy-MM-dd HH:mm'))"
    } else {
        $report['SoftwareDistribution'] = 'Not Found'
    }

    # -- catroot2 folder --
    $crPath = "$env:SystemRoot\System32\catroot2"
    if (Test-Path $crPath) {
        $crSize = (Get-ChildItem -Path $crPath -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
        $crSizeMB = [math]::Round($crSize / 1MB, 2)
        $crLastMod = (Get-Item $crPath -Force -ErrorAction SilentlyContinue).LastWriteTime
        $report['Catroot2'] = "$crSizeMB MB | Modified: $($crLastMod.ToString('yyyy-MM-dd HH:mm'))"
    } else {
        $report['Catroot2'] = 'Not Found'
    }

    # -- DISM CheckHealth --
    $dismResult = DISM /Online /Cleanup-Image /CheckHealth 2>&1
    $dismText = ($dismResult | Out-String)
    if ($dismText -match 'No component store corruption detected') {
        $report['DISMHealth'] = 'Healthy'
    } elseif ($dismText -match 'repairable') {
        $report['DISMHealth'] = 'Repairable'
    } else {
        $report['DISMHealth'] = 'Corrupted / Unknown'
    }

    # -- Pending reboot --
    $pendingReboot = $false
    $rebootPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($path in $rebootPaths) {
        if (Test-Path $path) { $pendingReboot = $true; break }
    }
    $report['PendingReboot'] = if ($pendingReboot) { 'Yes' } else { 'No' }

    # -- pending.xml --
    $pendingXml = "$env:SystemRoot\WinSxS\pending.xml"
    $report['PendingXml'] = if (Test-Path $pendingXml) { 'Present' } else { 'Not present' }

    # -- Last successful update --
    try {
        $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()
        if ($historyCount -gt 0) {
            $lastUpdate = $searcher.QueryHistory(0, 1) | Select-Object -First 1
            $report['LastSuccessfulUpdate'] = $lastUpdate.Date.ToString('yyyy-MM-dd HH:mm')
        } else {
            $report['LastSuccessfulUpdate'] = 'No history found'
        }
    } catch {
        $report['LastSuccessfulUpdate'] = 'Unable to query'
    }

    # -- Last 5 Windows Update errors from event log --
    $wuErrors = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
            Level = 2  # Error
        } -MaxEvents 5 -ErrorAction SilentlyContinue
        foreach ($evt in $events) {
            $wuErrors += [PSCustomObject]@{
                Time    = $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                Message = ($evt.Message -replace "`r`n|`n", ' ').Substring(0, [Math]::Min(100, $evt.Message.Length))
            }
        }
    } catch { }
    $report['WUErrors'] = $wuErrors

    # -- Hosts file scan --
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $blockedDomains = @()
    if (Test-Path $hostsPath) {
        $hostsContent = Get-Content -Path $hostsPath -ErrorAction SilentlyContinue
        foreach ($line in $hostsContent) {
            foreach ($domain in $Script:MicrosoftDomains) {
                if ($line -match [regex]::Escape($domain) -and $line -match '^\s*(0\.0\.0\.0|127\.0\.0\.1)\s+') {
                    $blockedDomains += $domain
                }
            }
        }
    }
    $blockedDomains = $blockedDomains | Sort-Object -Unique
    if ($blockedDomains.Count -gt 0) {
        $report['HostsStatus'] = "$($blockedDomains.Count) Microsoft block(s) found"
    }
    else {
        $report['HostsStatus'] = 'Clean'
    }

    # -- Display polished preflight snapshot --
    Write-UiSubheading -Title 'System overview'
    Write-UiMetric -Label 'Windows' -Value $report['OSSummary']
    Write-UiMetric -Label 'System drive' -Value $report['SystemDrive'] -Tone $(if ($report['FreeSpaceGB'] -ne $null -and $report['FreeSpaceGB'] -lt 10) { 'Warning' } else { 'Info' })
    Write-UiMetric -Label 'Hosts file' -Value $report['HostsStatus'] -Tone (Get-StatusTone $report['HostsStatus'])
    if ($report['IsLTSC']) {
        Write-UiMetric -Label 'Edition note' -Value 'LTSC / IoT detected - only security updates may be offered.' -Tone 'Warning'
    }

    Write-UiSubheading -Title 'Core services'
    foreach ($svc in $report['Services']) {
        Write-UiMetric -Label $svc.Component -Value $svc.Status -Tone (Get-StatusTone $svc.Status) -LabelWidth 34
    }

    Write-UiSubheading -Title 'Repair signals'
    $infoRows = @(
        @{ Label = 'SoftwareDistribution'; Value = $report['SoftwareDistribution'] },
        @{ Label = 'catroot2'; Value = $report['Catroot2'] },
        @{ Label = 'DISM health'; Value = $report['DISMHealth'] },
        @{ Label = 'Pending reboot'; Value = $report['PendingReboot'] },
        @{ Label = 'pending.xml'; Value = $report['PendingXml'] },
        @{ Label = 'Last successful update'; Value = $report['LastSuccessfulUpdate'] }
    )

    foreach ($row in $infoRows) {
        $tone = switch ($row.Label) {
            'Pending reboot' { if ($row.Value -eq 'Yes') { 'Warning' } else { 'Success' } }
            'pending.xml' { if ($row.Value -eq 'Present') { 'Warning' } else { 'Success' } }
            'DISM health' { switch ($row.Value) { 'Healthy' { 'Success' } 'Repairable' { 'Warning' } default { 'Error' } } }
            default { Get-StatusTone $row.Value }
        }
        Write-UiMetric -Label $row.Label -Value $row.Value -Tone $tone
    }

    if ($report['WUErrors'].Count -gt 0) {
        Write-UiCallout -Title 'Recent Windows Update errors' -Tone 'Warning' -Lines ($report['WUErrors'] | ForEach-Object {
            "[{0}] {1}" -f $_.Time, $_.Message
        })
    }
    else {
        Write-UiCallout -Title 'No recent Windows Update error events were found in the System log.' -Tone 'Success' -Lines @(
            'This usually means the machine is failing quietly through policy, service, cache, or connectivity issues instead of throwing recent update errors.'
        )
    }

    # Log all values
    Write-Log "Windows: $($report['OSSummary'])"
    Write-Log "System Drive: $($report['SystemDrive'])"
    Write-Log "Hosts File: $($report['HostsStatus'])"
    foreach ($svc in $report['Services']) {
        Write-Log "$($svc.Component): $($svc.Status)"
    }
    Write-Log "SoftwareDistribution: $($report['SoftwareDistribution'])"
    Write-Log "catroot2: $($report['Catroot2'])"
    Write-Log "DISM Health: $($report['DISMHealth'])"
    Write-Log "Pending Reboot: $($report['PendingReboot'])"
    Write-Log "pending.xml: $($report['PendingXml'])"
    Write-Log "Last Successful Update: $($report['LastSuccessfulUpdate'])"

    return $report
}

# ============================================================================
# HOSTS FILE REPAIR
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
# SSL/TLS CONFIGURATION REPAIR
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
# FIREWALL RULES REPAIR
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
# SERVICE DEPENDENCY REPAIR
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
# WINDOWS UPDATE POLICIES REPAIR
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
            Write-Log "  $($svc.Name): Not Found" -Level WARNING
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
# POST-REPAIR VERIFICATION (BEFORE/AFTER COMPARISON)
# ============================================================================

function Show-BeforeAfterComparison {
    param(
        [hashtable]$Before,
        [hashtable]$After
    )

    Write-Log "POST-REPAIR VERIFICATION - Before/After Comparison" -Level SECTION

    Write-UiSubheading -Title 'Service changes'
    foreach ($i in 0..($Before['Services'].Count - 1)) {
        $bSvc = $Before['Services'][$i]
        $aSvc = $After['Services'][$i]

        $tone = if ($bSvc.Status -ne $aSvc.Status) {
            if ($bSvc.Status -match 'Disabled|Stopped|Not Found' -and $aSvc.Status -notmatch 'Disabled|Stopped|Not Found') {
                'Success'
            }
            else {
                Get-StatusTone $aSvc.Status
            }
        }
        else {
            'Info'
        }

        Write-UiComparisonLine -Label $bSvc.Component -Before $bSvc.Status -After $aSvc.Status -Tone $tone -LabelWidth 34 -BeforeWidth 24
    }

    Write-UiSubheading -Title 'Repair signal changes'
    $compareKeys = @(
        @{ Key = 'HostsStatus'; Label = 'Hosts file' },
        @{ Key = 'SoftwareDistribution'; Label = 'SoftwareDistribution' },
        @{ Key = 'Catroot2'; Label = 'catroot2' },
        @{ Key = 'DISMHealth'; Label = 'DISM health' },
        @{ Key = 'PendingReboot'; Label = 'Pending reboot' },
        @{ Key = 'PendingXml'; Label = 'pending.xml' },
        @{ Key = 'LastSuccessfulUpdate'; Label = 'Last successful update' }
    )

    foreach ($item in $compareKeys) {
        $beforeValue = [string]$Before[$item.Key]
        $afterValue = [string]$After[$item.Key]

        $tone = switch ($item.Key) {
            'PendingReboot' { if ($afterValue -eq 'No') { 'Success' } else { 'Warning' } }
            'PendingXml' { if ($afterValue -eq 'Not present') { 'Success' } else { 'Warning' } }
            'DISMHealth' { switch ($afterValue) { 'Healthy' { 'Success' } 'Repairable' { 'Warning' } default { 'Error' } } }
            default {
                if ($beforeValue -ne $afterValue) { 'Success' } else { 'Info' }
            }
        }

        Write-UiComparisonLine -Label $item.Label -Before $beforeValue -After $afterValue -Tone $tone
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-WURepair {
    param(
        [switch]$SkipDISM,
        [switch]$SkipSFC,
        [switch]$SkipBackup,
        [switch]$QuickMode,
        [switch]$RepairServices,
        [switch]$RepairDLLs,
        [switch]$RepairStore,
        [switch]$RepairDISM,
        [switch]$RepairSFC,
        [switch]$RepairNetwork,
        [switch]$RepairAll
    )

    Show-Banner

    if (-not (Test-AdminRights)) {
        Write-Log "This script requires Administrator privileges!" -Level ERROR
        Write-Log "Please right-click and 'Run as Administrator'"
        return
    }

    # Initialize event log source
    Initialize-EventSource

    # Determine selective mode: if no specific -Repair* switch given, run all
    $selectiveMode = ($RepairServices -or $RepairDLLs -or $RepairStore -or $RepairDISM -or $RepairSFC -or $RepairNetwork)
    if ($RepairAll -or (-not $selectiveMode)) {
        # Full repair mode
        $RepairServices = $true
        $RepairDLLs     = $true
        $RepairStore    = $true
        $RepairDISM     = $true
        $RepairSFC      = $true
        $RepairNetwork  = $true
        $selectiveMode  = $false
    }

    # Override DISM/SFC if skip flags are set
    if ($SkipDISM -or $QuickMode) { $RepairDISM = $false }
    if ($SkipSFC -or $QuickMode) { $RepairSFC = $false }

    $startTime = Get-Date
    $modeLabel = if ($selectiveMode) { 'Targeted repair' } else { 'Full guided repair' }
    Write-Log "WURepair v$($Script:Config.Version) started at $startTime"
    Write-Log "Log file: $($Script:Config.LogPath)"

    Write-RepairEventLog -Message "WURepair v$($Script:Config.Version) started. Mode: $modeLabel" -EventId 1000

    # ── Diagnostic Pre-Check Report ──
    $preReport = Get-DiagnosticReport

    # Test connectivity
    $connectivity = Test-WindowsUpdateConnectivity

    $plannedSteps = @()
    if ($selectiveMode) {
        if ($RepairServices) { $plannedSteps += 'Reset Windows Update service configuration and restart core services.' }
        if ($RepairDLLs) { $plannedSteps += 'Re-register Windows Update and related system DLLs.' }
        if ($RepairStore) {
            $plannedSteps += if (-not $SkipBackup -and $Script:Config.CreateBackup) {
                'Rename and preserve SoftwareDistribution / catroot2 before rebuilding their contents.'
            } else {
                'Reset SoftwareDistribution / catroot2 without creating an extra folder backup.'
            }
        }
        if ($RepairDISM) { $plannedSteps += 'Run DISM to inspect and repair the component store.' }
        if ($RepairSFC) { $plannedSteps += 'Run System File Checker to repair protected Windows files.' }
        if ($RepairNetwork) { $plannedSteps += 'Reset Winsock and key network update paths.' }
    }
    else {
        $plannedSteps += @(
            'Clean Microsoft update blocks from the hosts file and restore key TLS settings.'
            'Repair firewall rules, service dependencies, and Windows Update blocking policies.'
            'Stop update-related services, refresh their configuration, and rebuild update caches.'
            'Re-register update DLLs, reset network components, and clean Windows Update registry state.'
        )
        if ($RepairDISM) { $plannedSteps += 'Run DISM repairs to heal the Windows component store.' }
        if ($RepairSFC) { $plannedSteps += 'Run System File Checker to validate and repair protected files.' }
    }

    $estimatedDuration = Get-EstimatedRepairDuration -SelectiveMode $selectiveMode -RepairDISM $RepairDISM -RepairSFC $RepairSFC -RepairNetwork $RepairNetwork -RepairStore $RepairStore
    $backupMode = if ($RepairStore) {
        if (-not $SkipBackup -and $Script:Config.CreateBackup) { 'Enabled before cache reset' } else { 'Skipped for cache reset' }
    }
    else {
        'Not needed for this run'
    }
    $restorePointMode = if ($selectiveMode) { 'Not created in targeted mode' } else { 'Attempted immediately after confirmation' }
    $connectivityLabel = if ($connectivity) { 'All tested Microsoft endpoints are reachable right now' } else { 'One or more update endpoints are currently failing' }

    Write-UiHeader -Title 'Repair plan ready' -Subtitle 'Review the scope below before any system changes are made.' -Tone 'Accent'
    Write-UiMetric -Label 'Mode' -Value $modeLabel -Tone 'Accent'
    Write-UiMetric -Label 'Estimated time' -Value $estimatedDuration -Tone 'Info'
    Write-UiMetric -Label 'Restart' -Value 'Required when repairs finish' -Tone 'Warning'
    Write-UiMetric -Label 'Backups' -Value $backupMode -Tone 'Info'
    Write-UiMetric -Label 'Restore point' -Value $restorePointMode -Tone $(if ($selectiveMode) { 'Info' } else { 'Success' })
    Write-UiMetric -Label 'Connectivity' -Value $connectivityLabel -Tone $(if ($connectivity) { 'Success' } else { 'Warning' })
    Write-UiMetric -Label 'Log file' -Value $Script:Config.LogPath -Tone 'Info'

    Write-UiList -Title 'Planned work' -Items $plannedSteps

    if ($preReport['PendingReboot'] -eq 'Yes') {
        Write-UiCallout -Title 'A reboot is already pending on this device.' -Tone 'Warning' -Lines @(
            'Windows Update can remain stuck until that restart is completed.',
            'Continuing is still safe, but the final reboot becomes especially important.'
        )
    }

    if ($preReport['HostsStatus'] -ne 'Clean') {
        Write-UiCallout -Title 'The hosts file is currently blocking Microsoft update domains.' -Tone 'Warning' -Lines @(
            'That is a common reason for 403 errors, scan failures, or empty update results.',
            'WURepair will remove only the known update-related block entries.'
        )
    }

    if (-not $connectivity) {
        Write-UiCallout -Title 'Connectivity is degraded before repair starts.' -Tone 'Warning' -Lines @(
            'This usually points to policy, DNS, TLS, firewall, VPN, or endpoint filtering issues.',
            'The repair flow will address the most common Windows Update causes automatically.'
        )
    }

    Write-UiCallout -Title 'Before you continue' -Tone 'Info' -Lines @(
        'WURepair focuses on Windows Update services, caches, policies, and connectivity settings.',
        'The tool does not remove user files, but it will stop services, rename update caches, and may request a restart.'
    )

    if (-not (Read-Confirmation -Prompt 'Start repair now')) {
        Write-Log "Operation cancelled by user" -Level WARNING
        return
    }

    if (-not $selectiveMode) {
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
    }

    # ── Build phase list for progress tracking ──
    $phases = @()
    if (-not $selectiveMode) {
        $phases += @{ Name = 'Repair Hosts File';          Action = { Repair-HostsFile } }
        $phases += @{ Name = 'Repair SSL/TLS';             Action = { Repair-TLSConfiguration } }
        $phases += @{ Name = 'Repair Firewall Rules';      Action = { Repair-FirewallRules } }
        $phases += @{ Name = 'Repair Service Dependencies'; Action = { Repair-ServiceDependencies } }
        $phases += @{ Name = 'Remove Blocking Policies';   Action = { Repair-UpdatePolicies } }
    }
    if ($RepairServices) {
        $phases += @{ Name = 'Stop WU Services';           Action = { Stop-WUServices } }
        $phases += @{ Name = 'Reset Service Config';       Action = { Reset-WUServiceConfig } }
    }
    if ($RepairStore) {
        if (-not $SkipBackup -and $Script:Config.CreateBackup) {
            $phases += @{ Name = 'Backup WU Folders';      Action = { Backup-WUFolders } }
        }
        $phases += @{ Name = 'Clear WU Cache';             Action = { Clear-WUCache } }
        $phases += @{ Name = 'Reset WU Registry';          Action = { Reset-WURegistry } }
        $phases += @{ Name = 'Reset WU Agent';             Action = { Reset-WindowsUpdateAgent } }
    }
    if ($RepairDLLs) {
        $phases += @{ Name = 'Re-register DLLs';           Action = { Register-WUDlls } }
    }
    if ($RepairNetwork) {
        $phases += @{ Name = 'Reset Network Stack';        Action = { Reset-WinsockCatalog } }
    }
    if ($RepairDISM) {
        $phases += @{ Name = 'DISM Repairs';               Action = { Invoke-DISM } }
    }
    if ($RepairSFC) {
        $phases += @{ Name = 'System File Checker';        Action = { Invoke-SFC } }
    }
    if ($RepairServices) {
        $phases += @{ Name = 'Start WU Services';          Action = { Start-WUServices } }
    }
    if (-not $selectiveMode) {
        $phases += @{ Name = 'Refresh Group Policy';       Action = { Update-GroupPolicy } }
    }

    $totalPhases = $phases.Count
    $currentPhase = 0

    foreach ($phase in $phases) {
        $currentPhase++
        $pct = [int](($currentPhase / $totalPhases) * 100)
        Write-Progress -Activity "WURepair v$($Script:Config.Version)" `
            -Status "Phase $currentPhase of $totalPhases : $($phase.Name)" `
            -PercentComplete $pct
        Write-Log "--- Phase $currentPhase of $totalPhases : $($phase.Name) ---"
        & $phase.Action
    }

    Write-Progress -Activity "WURepair v$($Script:Config.Version)" -Completed

    # ── Post-repair connectivity test ──
    Write-Log "POST-REPAIR CONNECTIVITY TEST" -Level SECTION
    $postConnectivity = Test-WindowsUpdateConnectivity

    # ── Post-repair verification: re-run diagnostic and compare ──
    $postReport = Get-DiagnosticReport
    Show-BeforeAfterComparison -Before $preReport -After $postReport

    # Trigger Windows Update check
    Invoke-WindowsUpdateCheck

    # ── Event log summary ──
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $durationMin = [math]::Round($duration.TotalMinutes, 1)

    $summaryLines = @(
        "WURepair v$($Script:Config.Version) completed."
        "Duration: $durationMin minutes"
        "Mode: $modeLabel"
        "Phases executed: $totalPhases"
        "Post-repair connectivity: $(if ($postConnectivity) { 'All endpoints reachable' } else { 'Some endpoints unreachable' })"
    )
    $summaryText = $summaryLines -join "`r`n"
    Write-RepairEventLog -Message $summaryText -EventId 1001

    # Summary
    Write-Log "COMPLETE - Windows Update Repair Finished" -Level SECTION
    Write-Log "Duration: $durationMin minutes"
    Write-Log "Log saved to: $($Script:Config.LogPath)"

    Write-UiHeader -Title 'Repair complete' -Subtitle 'Restart is strongly recommended to finalize service, cache, and policy changes.' -Tone 'Success'
    Write-UiMetric -Label 'Duration' -Value "$durationMin minutes" -Tone 'Info'
    Write-UiMetric -Label 'Mode' -Value $modeLabel -Tone 'Accent'
    Write-UiMetric -Label 'Phases executed' -Value ([string]$totalPhases) -Tone 'Info'
    Write-UiMetric -Label 'Connectivity after repair' -Value $(if ($postConnectivity) { 'All tested endpoints are reachable' } else { 'One or more endpoints are still failing' }) -Tone $(if ($postConnectivity) { 'Success' } else { 'Warning' })
    Write-UiMetric -Label 'Log file' -Value $Script:Config.LogPath -Tone 'Info'

    Write-UiList -Title 'Next steps' -Items @(
        'Restart Windows to complete the repair run.',
        'Open Settings > Windows Update and select Check for updates.',
        'If issues remain, review the saved log and the WURepair Application event log entry.'
    )

    if (-not $postConnectivity) {
        Write-UiCallout -Title 'Connectivity still needs attention after repair.' -Tone 'Warning' -Lines @(
            'Check for third-party antivirus, VPN, DNS filters, or corporate proxy controls that may still be intercepting update traffic.',
            'A restart should still be completed before you retest Windows Update.'
        )
    }

    if ($preReport['IsLTSC']) {
        Write-UiCallout -Title 'LTSC / IoT edition note' -Tone 'Info' -Lines @(
            'These editions normally receive security updates only.',
            'Feature updates not appearing is expected behavior, not a repair failure.'
        )
    }

    if (Read-Confirmation -Prompt 'Restart now') {
        Write-Log "Initiating restart..."
        Restart-Computer -Force
    }
    else {
        Write-Log "Restart deferred by user" -Level WARNING
    }
}

function Show-Help {
    Show-Banner

    Write-UiHeader -Title 'Usage' -Subtitle 'Full guided repair is the default. Add switches only when you want a narrower pass.' -Tone 'Accent'
    Write-UiMetric -Label 'Full repair' -Value '.\WURepair.ps1'
    Write-UiMetric -Label 'Quick repair' -Value '.\WURepair.ps1 -Quick'
    Write-UiMetric -Label 'Targeted repair' -Value '.\WURepair.ps1 -RepairStore -RepairDLLs'

    Write-UiList -Title 'Core options' -Items @(
        '-Quick or -QuickMode  Skip DISM and SFC for a faster pass.',
        '-SkipDISM             Skip only DISM component store repair.',
        '-SkipSFC              Skip only System File Checker.',
        '-SkipBackup           Skip extra cache folder backups before reset.',
        '-Help                 Show this help screen.'
    )

    Write-UiList -Title 'Targeted repair switches' -Items @(
        '-RepairServices  Reset and restart Windows Update services.',
        '-RepairDLLs      Re-register Windows Update DLLs.',
        '-RepairStore     Rebuild SoftwareDistribution and catroot2.',
        '-RepairDISM      Run DISM component store repair only.',
        '-RepairSFC       Run System File Checker only.',
        '-RepairNetwork   Reset network stack and update connectivity paths.',
        '-RepairAll       Force the full repair flow.'
    )

    Write-UiList -Title 'Examples' -Items @(
        '.\WURepair.ps1',
        '.\WURepair.ps1 -Quick',
        '.\WURepair.ps1 -RepairServices',
        '.\WURepair.ps1 -RepairStore -RepairDLLs',
        '.\WURepair.ps1 -SkipDISM'
    )

    Write-UiCallout -Title 'What the full repair flow covers' -Tone 'Info' -Lines @(
        'Hosts file cleanup, TLS repair, firewall and policy fixes, service reset, cache rebuild, DLL registration, network reset, DISM/SFC, and before/after verification.',
        'Administrator privileges are required and a restart is normally needed at the end.'
    )
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

$params = @{}

if ($args -contains '-SkipDISM') { $params['SkipDISM'] = $true }
if ($args -contains '-SkipSFC') { $params['SkipSFC'] = $true }
if ($args -contains '-SkipBackup') { $params['SkipBackup'] = $true }
if ($args -contains '-QuickMode' -or $args -contains '-Quick') { $params['QuickMode'] = $true }
if ($args -contains '-RepairServices') { $params['RepairServices'] = $true }
if ($args -contains '-RepairDLLs') { $params['RepairDLLs'] = $true }
if ($args -contains '-RepairStore') { $params['RepairStore'] = $true }
if ($args -contains '-RepairDISM') { $params['RepairDISM'] = $true }
if ($args -contains '-RepairSFC') { $params['RepairSFC'] = $true }
if ($args -contains '-RepairNetwork') { $params['RepairNetwork'] = $true }
if ($args -contains '-RepairAll') { $params['RepairAll'] = $true }

if ($args -contains '-Help' -or $args -contains '-?') {
    Show-Help
    exit
}

# Run the repair
Start-WURepair @params
