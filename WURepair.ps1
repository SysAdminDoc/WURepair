<#
.SYNOPSIS
    WURepair - Comprehensive Windows Update Repair Tool
.DESCRIPTION
    Thoroughly diagnoses, repairs, and resets Windows Update components.
    Includes service management, cache clearing, component re-registration,
    DISM/SFC integration, network resets, hosts file cleanup, firewall repair,
    SSL/TLS configuration, and detailed logging.

    v2.11.0 adds optional JSON repair reports for RMM ingestion.
    v2.10.0 adds Microsoft Update Catalog SSU repair fallback.
    v2.9.0 adds component store analysis before DISM cleanup.
    v2.8.0 adds optional Servicing Stack Update staging before DISM.
    v2.7.0 adds targeted Delivery Optimization repair.
    v2.6.0 adds targeted WaaS / Update Orchestrator repair.
    v2.5.0 adds WSUS/SUP posture diagnostics.
    v2.4.0 adds Microsoft Update Health Tools and remediation detection.
    v2.3.0 adds WaaSMedic and Delivery Optimization health diagnostics.
    v2.2.0 adds ranked Windows Update HRESULT summaries from WindowsUpdate.log
    and converted ETW traces.
    v2.1.0 adds diagnostic pre-check report, selective repair via parameters,
    progress tracking, event log integration, and post-repair verification
    with before/after comparison.
.NOTES
    Author: Matt Parker
    Requires: Administrator privileges
    Version: 2.11.0
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
    Version                            = '2.11.0'
    EventSource                        = 'WURepair'
    ComponentStoreResetBaseThresholdMB = 1024
    CatalogMaxCandidates               = 5
    Ui                                 = @{
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

$Script:WUErrorReferenceUrl = 'https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference'
$Script:WUErrorSearchUrl = 'https://learn.microsoft.com/search/?terms='
$Script:WUErrorArticleMap = @{
    '0x80070002' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x8007000D' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x80070020' = 'https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference'
    '0x80070422' = 'https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference'
    '0x80072EE2' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
    '0x80072EFE' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
    '0x80073712' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x8007371B' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x8007371C' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x8007371D' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x800F081F' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x800F0906' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x800F0922' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-server/installing-updates-features-roles/fix-windows-update-errors'
    '0x800F0923' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
    '0x8024401C' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
    '0x8024402C' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
    '0x8024500C' = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/installing-updates-features-roles/common-windows-update-errors'
}
$Script:WUTraceLogAttempted = $false
$Script:WUTraceLogPath = $null

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

    if ($Value -match 'Disabled|Not Found|BLOCKED|UNREACHABLE|DNS FAILURE|SSL/TLS ERROR|Corrupted|Unable|Unavailable|Failed|Not ready|Cache path missing|Inaccessible') {
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
        [bool]$RepairStore,
        [bool]$RepairWaaS,
        [bool]$RepairDelivery,
        [bool]$RepairServicingStack,
        [bool]$StageSSU
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
    if ($RepairWaaS) {
        $minMinutes += 1
        $maxMinutes += 3
    }
    if ($RepairDelivery) {
        $minMinutes += 1
        $maxMinutes += 3
    }
    if ($StageSSU -and $RepairDISM) {
        $minMinutes += 5
        $maxMinutes += 20
    }
    if ($RepairServicingStack) {
        $minMinutes += 5
        $maxMinutes += 25
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
# WINDOWS UPDATE LOG DIAGNOSTICS
# ============================================================================

function ConvertTo-WUErrorCode {
    param([AllowNull()][string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    $value = ([string]$Token).Trim()
    if ($value -match '^0x[0-9a-fA-F]{8}$') {
        return $value.ToUpperInvariant()
    }

    if ($value -match '^-?\d{7,12}$') {
        try {
            $number = [int64]$value
            if ($number -lt 0) {
                $number = 4294967296 + $number
            }

            if ($number -ge 0 -and $number -le 4294967295) {
                return ('0x{0:X8}' -f [uint32]$number)
            }
        }
        catch {
            return $null
        }
    }

    return $null
}

function Get-WUErrorArticleLink {
    param([string]$ErrorCode)

    $normalized = ConvertTo-WUErrorCode -Token $ErrorCode
    if (-not $normalized) {
        return $Script:WUErrorReferenceUrl
    }

    if ($Script:WUErrorArticleMap.ContainsKey($normalized)) {
        return $Script:WUErrorArticleMap[$normalized]
    }

    if ($normalized -match '^0x8024') {
        return $Script:WUErrorReferenceUrl
    }

    $query = [System.Uri]::EscapeDataString("$normalized Windows Update error")
    return "$($Script:WUErrorSearchUrl)$query"
}

function Get-WUConvertedTraceLogPath {
    if ($Script:WUTraceLogAttempted) {
        return $Script:WUTraceLogPath
    }

    $Script:WUTraceLogAttempted = $true

    try {
        $cmd = Get-Command -Name Get-WindowsUpdateLog -ErrorAction SilentlyContinue
        if (-not $cmd) {
            return $null
        }

        if (-not (Test-Path -LiteralPath $Script:Config.TempPath)) {
            New-Item -Path $Script:Config.TempPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $logPath = Join-Path $Script:Config.TempPath "WindowsUpdate_ETW_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $etlRoot = Join-Path $env:SystemRoot 'Logs\WindowsUpdate'

        if (Test-Path -LiteralPath $etlRoot) {
            $etlFiles = @(Get-ChildItem -LiteralPath $etlRoot -Filter '*.etl' -File -ErrorAction SilentlyContinue)
            if ($etlFiles.Count -gt 0) {
                Get-WindowsUpdateLog -ETLPath $etlRoot -LogPath $logPath -ErrorAction Stop | Out-Null
            }
            else {
                Get-WindowsUpdateLog -LogPath $logPath -ErrorAction Stop | Out-Null
            }
        }
        else {
            Get-WindowsUpdateLog -LogPath $logPath -ErrorAction Stop | Out-Null
        }

        if (Test-Path -LiteralPath $logPath) {
            $Script:WUTraceLogPath = $logPath
            return $logPath
        }
    }
    catch {
        Write-Log "Could not convert Windows Update ETW traces: $($_.Exception.Message)" -Level WARNING
    }

    return $null
}

function Get-WUErrorCodesFromLogFile {
    param(
        [string]$Path,
        [string]$Source
    )

    $results = New-Object 'System.Collections.Generic.List[object]'
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $lineNumber = 0
    try {
        Get-Content -LiteralPath $Path -ErrorAction Stop | ForEach-Object {
            $lineNumber++
            $line = [string]$_
            $tokens = @()

            foreach ($match in [regex]::Matches($line, '(?i)\b0x[0-9a-f]{8}\b')) {
                $tokens += $match.Value
            }
            foreach ($match in [regex]::Matches($line, '(?<![\w.])-?214[0-9]{7}(?![\w.])')) {
                $tokens += $match.Value
            }

            foreach ($token in $tokens) {
                $code = ConvertTo-WUErrorCode -Token $token
                if ($code) {
                    $context = $line.Trim()
                    if ($context.Length -gt 180) {
                        $context = $context.Substring(0, 177) + '...'
                    }

                    [void]$results.Add([PSCustomObject]@{
                        Code    = $code
                        Source  = $Source
                        Line    = $lineNumber
                        Context = $context
                    })
                }
            }
        }
    }
    catch {
        Write-Log "Could not parse ${Source}: $($_.Exception.Message)" -Level WARNING
    }

    return $results.ToArray()
}

function Get-WUErrorSummary {
    param([int]$MaxEntries = 10)

    $sources = @()
    $legacyLog = Join-Path $env:SystemRoot 'WindowsUpdate.log'
    if (Test-Path -LiteralPath $legacyLog) {
        $sources += [PSCustomObject]@{ Path = $legacyLog; Name = '%WINDIR%\WindowsUpdate.log' }
    }

    $traceLog = Get-WUConvertedTraceLogPath
    if ($traceLog) {
        $sources += [PSCustomObject]@{ Path = $traceLog; Name = 'Converted Windows Update ETW trace' }
    }

    $events = New-Object 'System.Collections.Generic.List[object]'
    foreach ($source in $sources) {
        foreach ($wuEvent in (Get-WUErrorCodesFromLogFile -Path $source.Path -Source $source.Name)) {
            [void]$events.Add($wuEvent)
        }
    }

    if ($events.Count -eq 0) {
        return @()
    }

    $summary = New-Object 'System.Collections.Generic.List[object]'
    foreach ($group in ($events | Group-Object -Property Code | Sort-Object -Property Count -Descending | Select-Object -First $MaxEntries)) {
        $sample = $group.Group | Select-Object -First 1
        $sourceList = ($group.Group | Select-Object -ExpandProperty Source -Unique) -join ', '
        [void]$summary.Add([PSCustomObject]@{
            Code      = $group.Name
            Count     = $group.Count
            Sources   = $sourceList
            Reference = Get-WUErrorArticleLink -ErrorCode $group.Name
            Example   = $sample.Context
        })
    }

    return $summary.ToArray()
}

function Format-WUByteSize {
    param([AllowNull()][object]$Bytes)

    if ($null -eq $Bytes) {
        return 'Unavailable'
    }

    try {
        $value = [double]$Bytes
    }
    catch {
        return 'Unavailable'
    }

    if ($value -lt 0) {
        return 'Unavailable'
    }

    if ($value -ge 1TB) { return ('{0:N2} TB' -f ($value / 1TB)) }
    if ($value -ge 1GB) { return ('{0:N2} GB' -f ($value / 1GB)) }
    if ($value -ge 1MB) { return ('{0:N2} MB' -f ($value / 1MB)) }
    if ($value -ge 1KB) { return ('{0:N2} KB' -f ($value / 1KB)) }
    return ('{0:N0} B' -f $value)
}

function Get-WUServiceStateLabel {
    param([string]$ServiceName)

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        return 'Not Found'
    }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    $startVal = (Get-ItemProperty -LiteralPath $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
    $startLabel = switch ($startVal) {
        0 { 'Boot' }
        1 { 'System' }
        2 { 'Automatic' }
        3 { 'Manual' }
        4 { 'Disabled' }
        default { 'Unknown' }
    }

    return "$($service.Status) ($startLabel)"
}

function Get-WURegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $property.$Name
    }
    catch {
        return $null
    }
}

function Format-WUPolicyValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 'Not configured'
    }

    return [string]$Value
}

function Get-WUNumericPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [string[]]$Names
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            try {
                return [double]$property.Value
            }
            catch {
                continue
            }
        }
    }

    return $null
}

function Measure-WUNumericPropertyTotal {
    param(
        [object[]]$InputObject,
        [string[]]$Names
    )

    $found = $false
    $total = 0.0

    foreach ($item in $InputObject) {
        foreach ($name in $Names) {
            $value = Get-WUNumericPropertyValue -InputObject $item -Names @($name)
            if ($null -ne $value) {
                $total += $value
                $found = $true
            }
        }
    }

    if ($found) {
        return $total
    }

    return $null
}

function Get-WaaSMedicDiagnostic {
    $serviceStatus = Get-WUServiceStateLabel -ServiceName 'WaaSMedicSvc'
    $taskSummary = 'Not available'
    $recentIssues = New-Object 'System.Collections.Generic.List[object]'

    try {
        $tasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\WaaSMedic\' -ErrorAction SilentlyContinue)
        if ($tasks.Count -gt 0) {
            $ready = @($tasks | Where-Object { $_.State -eq 'Ready' }).Count
            $running = @($tasks | Where-Object { $_.State -eq 'Running' }).Count
            $disabled = @($tasks | Where-Object { $_.State -eq 'Disabled' }).Count
            $taskSummary = "$($tasks.Count) task(s), $ready ready, $running running, $disabled disabled"
        }
        else {
            $taskSummary = 'No WaaSMedic scheduled tasks found'
        }
    }
    catch {
        $taskSummary = 'Unable to query scheduled tasks'
    }

    $logNames = @(
        'Microsoft-Windows-WaaSMedic/Operational',
        'Microsoft-Windows-WaaSMedicSvc/Operational'
    )

    foreach ($logName in $logNames) {
        try {
            $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName   = $logName
                Level     = @(2, 3)
                StartTime = (Get-Date).AddDays(-14)
            } -MaxEvents 5 -ErrorAction SilentlyContinue)

            foreach ($medicEvent in $events) {
                $message = $medicEvent.Message -replace "`r`n|`n", ' '
                if ($message.Length -gt 120) {
                    $message = $message.Substring(0, 117) + '...'
                }
                [void]$recentIssues.Add([PSCustomObject]@{
                    Time    = $medicEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                    LogName = $logName
                    Message = $message
                })
            }
        }
        catch {
            continue
        }
    }

    $recentIssueText = if ($recentIssues.Count -gt 0) {
        "$($recentIssues.Count) warning/error event(s) in the last 14 days"
    }
    else {
        'No recent warning/error events'
    }

    return [PSCustomObject]@{
        ServiceStatus = $serviceStatus
        TaskSummary   = $taskSummary
        RecentIssues  = $recentIssues.ToArray()
        IssueSummary  = $recentIssueText
    }
}

function Get-DeliveryOptimizationDiagnostic {
    $serviceStatus = Get-WUServiceStateLabel -ServiceName 'dosvc'
    $statusRows = @()
    $perfSnap = $null
    $statusAvailable = $false
    $perfAvailable = $false

    if (Get-Command -Name Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue) {
        try {
            $statusRows = @(Get-DeliveryOptimizationStatus -ErrorAction Stop -WarningAction SilentlyContinue)
            $statusAvailable = $true
        }
        catch {
            $statusRows = @()
        }
    }

    if (Get-Command -Name Get-DeliveryOptimizationPerfSnap -ErrorAction SilentlyContinue) {
        try {
            $perfSnap = Get-DeliveryOptimizationPerfSnap -ErrorAction Stop -WarningAction SilentlyContinue
            $perfAvailable = $true
        }
        catch {
            $perfSnap = $null
        }
    }

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    $downloadMode = $null
    if (Test-Path -LiteralPath $policyPath) {
        $downloadMode = (Get-ItemProperty -LiteralPath $policyPath -Name 'DODownloadMode' -ErrorAction SilentlyContinue).DODownloadMode
    }

    if ($null -eq $downloadMode -and $statusRows.Count -gt 0) {
        $downloadMode = Get-WUNumericPropertyValue -InputObject ($statusRows | Select-Object -First 1) -Names @('DODownloadMode', 'DownloadMode')
    }

    $downloadModeText = switch ([string]$downloadMode) {
        '0' { 'HTTP only / peering disabled' }
        '1' { 'LAN peering' }
        '2' { 'Group peering' }
        '3' { 'Internet peering' }
        '99' { 'Simple download mode' }
        '100' { 'Bypass mode' }
        '' { 'Not configured' }
        default {
            if ($null -eq $downloadMode) { 'Not configured' } else { "Mode $downloadMode" }
        }
    }

    $cachePath = "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
    if ($statusRows.Count -gt 0) {
        $statusCachePath = ($statusRows | Select-Object -First 1).PSObject.Properties['LocalCachePath']
        if ($null -ne $statusCachePath -and -not [string]::IsNullOrWhiteSpace([string]$statusCachePath.Value)) {
            $cachePath = [string]$statusCachePath.Value
        }
    }

    $cacheSize = $null
    $cacheStatus = try {
        if (-not (Test-Path -LiteralPath $cachePath -ErrorAction Stop)) {
            "Missing ($cachePath)"
        }
        else {
            try {
                $cacheSize = (Get-ChildItem -LiteralPath $cachePath -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                "Available ($cachePath)"
            }
            catch {
                "Available, size unreadable ($cachePath)"
            }
        }
    }
    catch {
        "Inaccessible ($cachePath)"
    }
    $bytesFromHttp = Get-WUNumericPropertyValue -InputObject $perfSnap -Names @('BytesFromHttp', 'BytesFromCDN')
    if ($null -eq $bytesFromHttp) {
        $bytesFromHttp = Measure-WUNumericPropertyTotal -InputObject $statusRows -Names @('BytesFromHttp', 'BytesFromCDN')
    }

    $bytesFromPeers = Measure-WUNumericPropertyTotal -InputObject @($perfSnap) -Names @('BytesFromPeers', 'BytesFromLanPeers', 'BytesFromGroupPeers', 'BytesFromInternetPeers')
    if ($null -eq $bytesFromPeers) {
        $bytesFromPeers = Measure-WUNumericPropertyTotal -InputObject $statusRows -Names @('BytesFromPeers', 'BytesFromLanPeers', 'BytesFromGroupPeers', 'BytesFromInternetPeers')
    }

    $bytesToPeers = Measure-WUNumericPropertyTotal -InputObject @($perfSnap) -Names @('BytesToPeers', 'BytesToLanPeers', 'BytesToGroupPeers', 'BytesToInternetPeers')
    if ($null -eq $bytesToPeers) {
        $bytesToPeers = Measure-WUNumericPropertyTotal -InputObject $statusRows -Names @('BytesToPeers', 'BytesToLanPeers', 'BytesToGroupPeers', 'BytesToInternetPeers')
    }

    $peerCount = Get-WUNumericPropertyValue -InputObject $perfSnap -Names @('NumberOfPeers', 'PeerCount')
    if ($null -eq $peerCount -and $statusRows.Count -gt 0) {
        $peerCount = Measure-WUNumericPropertyTotal -InputObject $statusRows -Names @('NumberOfPeers', 'PeerCount')
    }

    $peerCacheHealth = if ($serviceStatus -match 'Not Found|Disabled') {
        'Not ready - Delivery Optimization service unavailable'
    }
    elseif (-not $statusAvailable -and -not $perfAvailable) {
        'Cmdlets unavailable - cannot inspect peer cache'
    }
    elseif ($downloadModeText -match 'disabled|Simple|Bypass') {
        "Peering limited - $downloadModeText"
    }
    elseif ($cacheStatus -match '^Missing') {
        'Cache path missing'
    }
    elseif (($null -ne $bytesFromPeers -and $bytesFromPeers -gt 0) -or ($null -ne $bytesToPeers -and $bytesToPeers -gt 0)) {
        'Peer activity observed'
    }
    else {
        'Ready; no peer activity observed'
    }

    return [PSCustomObject]@{
        ServiceStatus      = $serviceStatus
        DownloadMode       = $downloadModeText
        ActiveJobs         = $statusRows.Count
        PeerCacheHealth    = $peerCacheHealth
        CacheStatus        = $cacheStatus
        CacheSize          = Format-WUByteSize -Bytes $cacheSize
        BytesFromHttp      = Format-WUByteSize -Bytes $bytesFromHttp
        BytesFromPeers     = Format-WUByteSize -Bytes $bytesFromPeers
        BytesToPeers       = Format-WUByteSize -Bytes $bytesToPeers
        PeerCount          = if ($null -eq $peerCount) { 'Unavailable' } else { [string][int]$peerCount }
        StatusCmdlet       = if ($statusAvailable) { 'Available' } else { 'Unavailable' }
        PerfSnapCmdlet     = if ($perfAvailable) { 'Available' } else { 'Unavailable' }
    }
}

function Get-UpdateHealthToolDiagnostic {
    $installPaths = New-Object 'System.Collections.Generic.List[string]'
    $uninstallEntries = New-Object 'System.Collections.Generic.List[object]'
    $versions = New-Object 'System.Collections.Generic.List[string]'

    $candidatePaths = @(
        "$env:ProgramFiles\Microsoft Update Health Tools",
        "${env:ProgramFiles(x86)}\Microsoft Update Health Tools",
        "$env:ProgramFiles\rempl",
        "${env:ProgramFiles(x86)}\rempl"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidatePath in $candidatePaths) {
        try {
            if (Test-Path -LiteralPath $candidatePath -ErrorAction Stop) {
                [void]$installPaths.Add($candidatePath)
                $exe = Get-ChildItem -LiteralPath $candidatePath -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) {
                    $fileVersion = $exe.VersionInfo.ProductVersion
                    if ([string]::IsNullOrWhiteSpace($fileVersion)) {
                        $fileVersion = $exe.VersionInfo.FileVersion
                    }
                    if (-not [string]::IsNullOrWhiteSpace($fileVersion) -and -not $versions.Contains($fileVersion)) {
                        [void]$versions.Add($fileVersion)
                    }
                }
            }
        }
        catch {
            continue
        }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        try {
            foreach ($child in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $entry = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction SilentlyContinue
                if ($entry.DisplayName -match 'Microsoft Update Health Tools|Update Health Tools|Windows Setup Remediations') {
                    [void]$uninstallEntries.Add([PSCustomObject]@{
                        DisplayName    = $entry.DisplayName
                        DisplayVersion = $entry.DisplayVersion
                        Publisher      = $entry.Publisher
                    })
                    if (-not [string]::IsNullOrWhiteSpace($entry.DisplayVersion) -and -not $versions.Contains([string]$entry.DisplayVersion)) {
                        [void]$versions.Add([string]$entry.DisplayVersion)
                    }
                }
            }
        }
        catch {
            continue
        }
    }

    $healthService = Get-WUServiceStateLabel -ServiceName 'uhssvc'
    $remediationService = Get-WUServiceStateLabel -ServiceName 'sedsvc'
    $sedLauncherProcesses = @(Get-Process -Name 'sedlauncher' -ErrorAction SilentlyContinue)
    $sedSvcProcesses = @(Get-Process -Name 'sedsvc' -ErrorAction SilentlyContinue)
    $remediationProcesses = @(Get-Process -Name 'rempl', 'remsh', 'WaaSMedicAgent' -ErrorAction SilentlyContinue)

    $remplTaskSummary = 'Not available'
    try {
        $tasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\rempl\' -ErrorAction SilentlyContinue)
        if ($tasks.Count -gt 0) {
            $ready = @($tasks | Where-Object { $_.State -eq 'Ready' }).Count
            $running = @($tasks | Where-Object { $_.State -eq 'Running' }).Count
            $disabled = @($tasks | Where-Object { $_.State -eq 'Disabled' }).Count
            $remplTaskSummary = "$($tasks.Count) task(s), $ready ready, $running running, $disabled disabled"
        }
        else {
            $remplTaskSummary = 'No rempl scheduled tasks found'
        }
    }
    catch {
        $remplTaskSummary = 'Unable to query scheduled tasks'
    }

    $installed = (
        $installPaths.Count -gt 0 -or
        $uninstallEntries.Count -gt 0 -or
        $healthService -ne 'Not Found' -or
        $remediationService -ne 'Not Found'
    )

    $presence = if ($installed) { 'Detected' } else { 'Not detected' }
    $installPathText = if ($installPaths.Count -gt 0) { ($installPaths.ToArray() -join '; ') } else { 'Not found' }
    $versionText = if ($versions.Count -gt 0) { ($versions.ToArray() -join ', ') } else { 'Unknown' }
    $sedLauncherText = if ($sedLauncherProcesses.Count -gt 0) { "Running ($($sedLauncherProcesses.Count) process(es))" } else { 'Not running' }
    $sedSvcProcessText = if ($sedSvcProcesses.Count -gt 0) { "Running ($($sedSvcProcesses.Count) process(es))" } else { 'Not running' }
    $remediationProcessText = if ($remediationProcesses.Count -gt 0) {
        (($remediationProcesses | Group-Object -Property ProcessName | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')
    }
    else {
        'Not running'
    }

    return [PSCustomObject]@{
        Presence                 = $presence
        InstallPaths             = $installPathText
        Versions                 = $versionText
        PackageCount             = $uninstallEntries.Count
        UpdateHealthService      = $healthService
        RemediationService       = $remediationService
        SedLauncherStatus        = $sedLauncherText
        SedSvcProcessStatus      = $sedSvcProcessText
        RemediationProcessStatus = $remediationProcessText
        RemplTaskSummary         = $remplTaskSummary
    }
}

function Resolve-WUUrlDiagnostic {
    param([AllowNull()][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return 'Not configured'
    }

    try {
        $uri = [System.Uri]$Url
        if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            return "Invalid URL: $Url"
        }

        $addresses = @([System.Net.Dns]::GetHostAddresses($uri.Host))
        if ($addresses.Count -eq 0) {
            return "$($uri.Host) -> no DNS records"
        }

        $addressText = ($addresses | Select-Object -First 3 | ForEach-Object { $_.IPAddressToString }) -join ', '
        if ($addresses.Count -gt 3) {
            $addressText = "$addressText, ..."
        }
        return "$($uri.Host) -> $addressText"
    }
    catch {
        return "Unresolved: $Url ($($_.Exception.Message))"
    }
}

function Get-WSUSPostureDiagnostic {
    $wuPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $issues = New-Object 'System.Collections.Generic.List[string]'

    $wuServer = Get-WURegistryValue -Path $wuPolicyPath -Name 'WUServer'
    $wuStatusServer = Get-WURegistryValue -Path $wuPolicyPath -Name 'WUStatusServer'
    $targetGroup = Get-WURegistryValue -Path $wuPolicyPath -Name 'TargetGroup'
    $targetGroupEnabled = Get-WURegistryValue -Path $wuPolicyPath -Name 'TargetGroupEnabled'
    $disableDualScan = Get-WURegistryValue -Path $wuPolicyPath -Name 'DisableDualScan'
    $doNotConnect = Get-WURegistryValue -Path $wuPolicyPath -Name 'DoNotConnectToWindowsUpdateInternetLocations'
    $useWUServer = Get-WURegistryValue -Path $auPolicyPath -Name 'UseWUServer'
    $setQualitySource = Get-WURegistryValue -Path $wuPolicyPath -Name 'SetPolicyDrivenUpdateSourceForQualityUpdates'
    $setFeatureSource = Get-WURegistryValue -Path $wuPolicyPath -Name 'SetPolicyDrivenUpdateSourceForFeatureUpdates'
    $setDriverSource = Get-WURegistryValue -Path $wuPolicyPath -Name 'SetPolicyDrivenUpdateSourceForDriverUpdates'
    $setOtherSource = Get-WURegistryValue -Path $wuPolicyPath -Name 'SetPolicyDrivenUpdateSourceForOtherUpdates'

    if ($useWUServer -eq 1 -and [string]::IsNullOrWhiteSpace([string]$wuServer)) {
        [void]$issues.Add('UseWUServer is enabled but WUServer is empty')
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$wuServer) -and -not [string]::IsNullOrWhiteSpace([string]$wuStatusServer)) {
        try {
            $serverUri = [System.Uri]$wuServer
            $statusUri = [System.Uri]$wuStatusServer
            if ($serverUri.Host -and $statusUri.Host -and $serverUri.Host -ne $statusUri.Host) {
                [void]$issues.Add('WUServer and WUStatusServer point to different hosts')
            }
        }
        catch {
            [void]$issues.Add('WUServer or WUStatusServer is not a valid absolute URL')
        }
    }

    if ($targetGroupEnabled -eq 1 -and [string]::IsNullOrWhiteSpace([string]$targetGroup)) {
        [void]$issues.Add('TargetGroupEnabled is set but TargetGroup is empty')
    }

    if ($doNotConnect -eq 1 -and $useWUServer -ne 1) {
        [void]$issues.Add('Online Windows Update access is disabled but WSUS is not enabled')
    }

    $sourcePolicyValues = @($setQualitySource, $setFeatureSource, $setDriverSource, $setOtherSource) | Where-Object { $null -ne $_ }
    $sourcePolicySummary = if ($sourcePolicyValues.Count -gt 0) {
        "Quality=$setQualitySource; Feature=$setFeatureSource; Driver=$setDriverSource; Other=$setOtherSource"
    }
    else {
        'Not configured'
    }

    $dualScanText = switch ([string]$disableDualScan) {
        '1' { 'Disabled by policy' }
        '0' { 'Allowed' }
        '' { 'Not configured' }
        default {
            if ($null -eq $disableDualScan) { 'Not configured' } else { "Value $disableDualScan" }
        }
    }

    $posture = if ($issues.Count -gt 0) {
        "$($issues.Count) issue(s) detected"
    }
    elseif ($useWUServer -eq 1) {
        'WSUS/SUP configured'
    }
    elseif ($sourcePolicyValues.Count -gt 0) {
        'WUfB source policy configured'
    }
    else {
        'Direct Windows Update / default policy'
    }

    return [PSCustomObject]@{
        PostureSummary       = $posture
        Issues               = $issues.ToArray()
        UseWUServer          = Format-WUPolicyValue -Value $useWUServer
        WUServer             = Format-WUPolicyValue -Value $wuServer
        WUStatusServer       = Format-WUPolicyValue -Value $wuStatusServer
        WUServerResolution   = Resolve-WUUrlDiagnostic -Url $wuServer
        StatusResolution     = Resolve-WUUrlDiagnostic -Url $wuStatusServer
        TargetGroup          = Format-WUPolicyValue -Value $targetGroup
        TargetGroupEnabled   = Format-WUPolicyValue -Value $targetGroupEnabled
        DualScanPolicy       = $dualScanText
        DoNotConnect         = Format-WUPolicyValue -Value $doNotConnect
        SourcePolicy         = $sourcePolicySummary
    }
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

    # -- WaaSMedic and Delivery Optimization diagnostics --
    $waaSMedic = Get-WaaSMedicDiagnostic
    $deliveryOptimization = Get-DeliveryOptimizationDiagnostic
    $updateHealthTools = Get-UpdateHealthToolDiagnostic
    $wsusPosture = Get-WSUSPostureDiagnostic
    $report['WaaSMedic'] = $waaSMedic
    $report['DeliveryOptimization'] = $deliveryOptimization
    $report['UpdateHealthTools'] = $updateHealthTools
    $report['WSUSPosture'] = $wsusPosture
    $report['WaaSMedicStatus'] = $waaSMedic.ServiceStatus
    $report['DeliveryOptimizationPeerCache'] = $deliveryOptimization.PeerCacheHealth
    $report['DeliveryOptimizationMode'] = $deliveryOptimization.DownloadMode
    $report['UpdateHealthToolsStatus'] = $updateHealthTools.Presence
    $report['UpdateHealthServiceStatus'] = $updateHealthTools.UpdateHealthService
    $report['RemediationServiceStatus'] = $updateHealthTools.RemediationService
    $report['WSUSPostureSummary'] = $wsusPosture.PostureSummary
    $report['UseWUServer'] = $wsusPosture.UseWUServer
    $report['DualScanPolicy'] = $wsusPosture.DualScanPolicy

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

    # -- Ranked HRESULT summary from WindowsUpdate.log and converted ETW traces --
    $wuErrorSummary = Get-WUErrorSummary -MaxEntries 10
    $report['WUErrorSummary'] = $wuErrorSummary
    if ($wuErrorSummary.Count -gt 0) {
        $topWUError = $wuErrorSummary | Select-Object -First 1
        $report['TopWUError'] = "$($topWUError.Code) x$($topWUError.Count)"
    }
    else {
        $report['TopWUError'] = 'None found'
    }

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

    Write-UiSubheading -Title 'WaaSMedic, Update Health, and Delivery Optimization'
    Write-UiMetric -Label 'WaaSMedic service' -Value $report['WaaSMedic'].ServiceStatus -Tone (Get-StatusTone $report['WaaSMedic'].ServiceStatus)
    Write-UiMetric -Label 'WaaSMedic tasks' -Value $report['WaaSMedic'].TaskSummary -Tone (Get-StatusTone $report['WaaSMedic'].TaskSummary)
    Write-UiMetric -Label 'WaaSMedic events' -Value $report['WaaSMedic'].IssueSummary -Tone (Get-StatusTone $report['WaaSMedic'].IssueSummary)
    Write-UiMetric -Label 'Update Health Tools' -Value $report['UpdateHealthTools'].Presence -Tone (Get-StatusTone $report['UpdateHealthTools'].Presence)
    Write-UiMetric -Label 'Update Health version' -Value $report['UpdateHealthTools'].Versions -Tone 'Info'
    Write-UiMetric -Label 'Update Health path' -Value $report['UpdateHealthTools'].InstallPaths -Tone (Get-StatusTone $report['UpdateHealthTools'].InstallPaths)
    Write-UiMetric -Label 'Update Health service' -Value $report['UpdateHealthTools'].UpdateHealthService -Tone (Get-StatusTone $report['UpdateHealthTools'].UpdateHealthService)
    Write-UiMetric -Label 'Remediation service' -Value $report['UpdateHealthTools'].RemediationService -Tone (Get-StatusTone $report['UpdateHealthTools'].RemediationService)
    Write-UiMetric -Label 'sedlauncher' -Value $report['UpdateHealthTools'].SedLauncherStatus -Tone (Get-StatusTone $report['UpdateHealthTools'].SedLauncherStatus)
    Write-UiMetric -Label 'sedsvc process' -Value $report['UpdateHealthTools'].SedSvcProcessStatus -Tone (Get-StatusTone $report['UpdateHealthTools'].SedSvcProcessStatus)
    Write-UiMetric -Label 'rempl tasks' -Value $report['UpdateHealthTools'].RemplTaskSummary -Tone (Get-StatusTone $report['UpdateHealthTools'].RemplTaskSummary)
    Write-UiMetric -Label 'DO service' -Value $report['DeliveryOptimization'].ServiceStatus -Tone (Get-StatusTone $report['DeliveryOptimization'].ServiceStatus)
    Write-UiMetric -Label 'DO download mode' -Value $report['DeliveryOptimization'].DownloadMode -Tone (Get-StatusTone $report['DeliveryOptimization'].DownloadMode)
    Write-UiMetric -Label 'DO peer cache' -Value $report['DeliveryOptimization'].PeerCacheHealth -Tone (Get-StatusTone $report['DeliveryOptimization'].PeerCacheHealth)
    Write-UiMetric -Label 'DO cache size' -Value $report['DeliveryOptimization'].CacheSize -Tone 'Info'
    Write-UiMetric -Label 'DO active jobs' -Value ([string]$report['DeliveryOptimization'].ActiveJobs) -Tone 'Info'
    Write-UiMetric -Label 'DO bytes from HTTP' -Value $report['DeliveryOptimization'].BytesFromHttp -Tone 'Info'
    Write-UiMetric -Label 'DO bytes from peers' -Value $report['DeliveryOptimization'].BytesFromPeers -Tone 'Info'
    Write-UiMetric -Label 'DO bytes to peers' -Value $report['DeliveryOptimization'].BytesToPeers -Tone 'Info'
    Write-UiMetric -Label 'DO peer count' -Value $report['DeliveryOptimization'].PeerCount -Tone 'Info'

    Write-UiSubheading -Title 'WSUS / SUP posture'
    Write-UiMetric -Label 'Posture' -Value $report['WSUSPosture'].PostureSummary -Tone (Get-StatusTone $report['WSUSPosture'].PostureSummary)
    Write-UiMetric -Label 'UseWUServer' -Value $report['WSUSPosture'].UseWUServer -Tone (Get-StatusTone $report['WSUSPosture'].UseWUServer)
    Write-UiMetric -Label 'WUServer' -Value $report['WSUSPosture'].WUServer -Tone (Get-StatusTone $report['WSUSPosture'].WUServer)
    Write-UiMetric -Label 'WUServer DNS' -Value $report['WSUSPosture'].WUServerResolution -Tone (Get-StatusTone $report['WSUSPosture'].WUServerResolution)
    Write-UiMetric -Label 'WUStatusServer' -Value $report['WSUSPosture'].WUStatusServer -Tone (Get-StatusTone $report['WSUSPosture'].WUStatusServer)
    Write-UiMetric -Label 'WUStatus DNS' -Value $report['WSUSPosture'].StatusResolution -Tone (Get-StatusTone $report['WSUSPosture'].StatusResolution)
    Write-UiMetric -Label 'Target group' -Value $report['WSUSPosture'].TargetGroup -Tone (Get-StatusTone $report['WSUSPosture'].TargetGroup)
    Write-UiMetric -Label 'Target enabled' -Value $report['WSUSPosture'].TargetGroupEnabled -Tone (Get-StatusTone $report['WSUSPosture'].TargetGroupEnabled)
    Write-UiMetric -Label 'Dual scan' -Value $report['WSUSPosture'].DualScanPolicy -Tone (Get-StatusTone $report['WSUSPosture'].DualScanPolicy)
    Write-UiMetric -Label 'Online WU disabled' -Value $report['WSUSPosture'].DoNotConnect -Tone (Get-StatusTone $report['WSUSPosture'].DoNotConnect)
    Write-UiMetric -Label 'Source policies' -Value $report['WSUSPosture'].SourcePolicy -Tone (Get-StatusTone $report['WSUSPosture'].SourcePolicy)
    foreach ($wsusIssue in $report['WSUSPosture'].Issues) {
        Write-UiMetric -Label 'WSUS issue' -Value $wsusIssue -Tone 'Warning'
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

    if ($report['WUErrorSummary'].Count -gt 0) {
        Write-UiSubheading -Title 'Ranked Windows Update HRESULTs'
        foreach ($entry in $report['WUErrorSummary']) {
            Write-UiMetric -Label "$($entry.Code) x$($entry.Count)" -Value $entry.Reference -Tone 'Warning' -LabelWidth 18
            Write-UiMetric -Label 'Sources' -Value $entry.Sources -Tone 'Info' -LabelWidth 18
        }
    }
    else {
        Write-UiCallout -Title 'No HRESULTs were found in WindowsUpdate.log or converted ETW traces.' -Tone 'Success' -Lines @(
            'This points attention back to policy, service, cache, connectivity, or event-log failures.'
        )
    }

    # Log all values
    Write-Log "Windows: $($report['OSSummary'])"
    Write-Log "System Drive: $($report['SystemDrive'])"
    Write-Log "Hosts File: $($report['HostsStatus'])"
    foreach ($svc in $report['Services']) {
        Write-Log "$($svc.Component): $($svc.Status)"
    }
    Write-Log "WaaSMedic Service: $($report['WaaSMedic'].ServiceStatus)"
    Write-Log "WaaSMedic Tasks: $($report['WaaSMedic'].TaskSummary)"
    Write-Log "WaaSMedic Events: $($report['WaaSMedic'].IssueSummary)"
    foreach ($medicIssue in $report['WaaSMedic'].RecentIssues) {
        Write-Log "WaaSMedic Event: [$($medicIssue.Time)] $($medicIssue.LogName) - $($medicIssue.Message)"
    }
    Write-Log "Update Health Tools: $($report['UpdateHealthTools'].Presence)"
    Write-Log "Update Health Tools Versions: $($report['UpdateHealthTools'].Versions)"
    Write-Log "Update Health Tools Paths: $($report['UpdateHealthTools'].InstallPaths)"
    Write-Log "Update Health Service: $($report['UpdateHealthTools'].UpdateHealthService)"
    Write-Log "Windows Remediation Service: $($report['UpdateHealthTools'].RemediationService)"
    Write-Log "sedlauncher: $($report['UpdateHealthTools'].SedLauncherStatus)"
    Write-Log "sedsvc process: $($report['UpdateHealthTools'].SedSvcProcessStatus)"
    Write-Log "Remediation processes: $($report['UpdateHealthTools'].RemediationProcessStatus)"
    Write-Log "rempl tasks: $($report['UpdateHealthTools'].RemplTaskSummary)"
    Write-Log "Delivery Optimization Service: $($report['DeliveryOptimization'].ServiceStatus)"
    Write-Log "Delivery Optimization Mode: $($report['DeliveryOptimization'].DownloadMode)"
    Write-Log "Delivery Optimization Peer Cache: $($report['DeliveryOptimization'].PeerCacheHealth)"
    Write-Log "Delivery Optimization Cache: $($report['DeliveryOptimization'].CacheStatus)"
    Write-Log "Delivery Optimization Cache Size: $($report['DeliveryOptimization'].CacheSize)"
    Write-Log "Delivery Optimization Active Jobs: $($report['DeliveryOptimization'].ActiveJobs)"
    Write-Log "Delivery Optimization Bytes From HTTP: $($report['DeliveryOptimization'].BytesFromHttp)"
    Write-Log "Delivery Optimization Bytes From Peers: $($report['DeliveryOptimization'].BytesFromPeers)"
    Write-Log "Delivery Optimization Bytes To Peers: $($report['DeliveryOptimization'].BytesToPeers)"
    Write-Log "Delivery Optimization Peer Count: $($report['DeliveryOptimization'].PeerCount)"
    Write-Log "WSUS/SUP Posture: $($report['WSUSPosture'].PostureSummary)"
    Write-Log "UseWUServer: $($report['WSUSPosture'].UseWUServer)"
    Write-Log "WUServer: $($report['WSUSPosture'].WUServer)"
    Write-Log "WUServer DNS: $($report['WSUSPosture'].WUServerResolution)"
    Write-Log "WUStatusServer: $($report['WSUSPosture'].WUStatusServer)"
    Write-Log "WUStatusServer DNS: $($report['WSUSPosture'].StatusResolution)"
    Write-Log "TargetGroup: $($report['WSUSPosture'].TargetGroup)"
    Write-Log "TargetGroupEnabled: $($report['WSUSPosture'].TargetGroupEnabled)"
    Write-Log "DualScanPolicy: $($report['WSUSPosture'].DualScanPolicy)"
    Write-Log "DoNotConnectToWindowsUpdateInternetLocations: $($report['WSUSPosture'].DoNotConnect)"
    Write-Log "Policy-driven update sources: $($report['WSUSPosture'].SourcePolicy)"
    foreach ($wsusIssue in $report['WSUSPosture'].Issues) {
        Write-Log "WSUS/SUP Issue: $wsusIssue" -Level WARNING
    }
    Write-Log "SoftwareDistribution: $($report['SoftwareDistribution'])"
    Write-Log "catroot2: $($report['Catroot2'])"
    Write-Log "DISM Health: $($report['DISMHealth'])"
    Write-Log "Pending Reboot: $($report['PendingReboot'])"
    Write-Log "pending.xml: $($report['PendingXml'])"
    Write-Log "Last Successful Update: $($report['LastSuccessfulUpdate'])"
    if ($report['WUErrorSummary'].Count -gt 0) {
        foreach ($entry in $report['WUErrorSummary']) {
            Write-Log "WU HRESULT: $($entry.Code) x$($entry.Count) | Sources: $($entry.Sources) | Reference: $($entry.Reference)"
        }
    }
    else {
        Write-Log "WU HRESULT summary: no matching HRESULTs found in WindowsUpdate.log or converted ETW traces"
    }

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

function Wait-WUServiceState {
    param(
        [string]$ServiceName,
        [string]$DesiredState,
        [int]$TimeoutSeconds = 20
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service -and [string]$service.Status -eq $DesiredState) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    return $false
}

function Repair-WaaSOrchestrator {
    Write-Log "WAAS - Resetting Update Orchestrator and USO Tasks" -Level SECTION

    $serviceNames = @('UsoSvc', 'WaaSMedicSvc')
    $serviceWasRunning = @{}

    foreach ($serviceName in $serviceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "$serviceName service not found" -Level WARNING
            continue
        }

        $serviceWasRunning[$serviceName] = ($service.Status -eq 'Running')
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        try {
            $startValue = (Get-ItemProperty -LiteralPath $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
            if ($startValue -eq 4) {
                Set-ItemProperty -LiteralPath $regPath -Name 'Start' -Value 3 -Type DWord -Force -ErrorAction Stop
                Write-Log "$serviceName was disabled, set to Manual" -Level SUCCESS
            }
        }
        catch {
            Write-Log "Could not adjust $serviceName startup type: $($_.Exception.Message)" -Level WARNING
        }

        if ($service.Status -eq 'Running') {
            Write-Log "Stopping $serviceName with sc.exe..."
            $stopOutput = & sc.exe stop $serviceName 2>&1
            if ($LASTEXITCODE -eq 0 -and (Wait-WUServiceState -ServiceName $serviceName -DesiredState 'Stopped' -TimeoutSeconds 20)) {
                Write-Log "$serviceName stopped" -Level SUCCESS
            }
            else {
                Write-Log "Could not confirm $serviceName stopped: $($stopOutput -join ' ')" -Level WARNING
            }
        }
    }

    try {
        $tasks = @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' -ErrorAction Stop)
        $enabledCount = 0
        foreach ($task in $tasks) {
            if ($task.State -eq 'Disabled') {
                try {
                    Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
                    $enabledCount++
                }
                catch {
                    Write-Log "Could not enable Update Orchestrator task $($task.TaskName): $($_.Exception.Message)" -Level WARNING
                }
            }
        }

        Write-Log "Update Orchestrator tasks checked: $($tasks.Count); enabled: $enabledCount" -Level SUCCESS

        $scanTask = $tasks | Where-Object { $_.TaskName -in @('Schedule Scan', 'Schedule Scan Static Task') } | Select-Object -First 1
        if ($scanTask) {
            Write-Log "Schedule Scan task is present: $($scanTask.TaskName)" -Level SUCCESS
        }
        else {
            Write-Log "Schedule Scan task was not found under Update Orchestrator" -Level WARNING
        }
    }
    catch {
        Write-Log "Could not query Update Orchestrator scheduled tasks: $($_.Exception.Message)" -Level WARNING
    }

    $usoClient = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
    if (Test-Path -LiteralPath $usoClient) {
        try {
            Start-Process -FilePath $usoClient -ArgumentList 'RefreshSettings' -WindowStyle Hidden -Wait -ErrorAction Stop
            Write-Log "USO settings refreshed" -Level SUCCESS
        }
        catch {
            Write-Log "Could not refresh USO settings: $($_.Exception.Message)" -Level WARNING
        }
    }
    else {
        Write-Log "UsoClient.exe not found" -Level WARNING
    }

    foreach ($serviceName in $serviceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            continue
        }

        if ($serviceWasRunning[$serviceName] -or $serviceName -eq 'UsoSvc') {
            Write-Log "Starting $serviceName with sc.exe..."
            $startOutput = & sc.exe start $serviceName 2>&1
            if ($LASTEXITCODE -eq 0 -and (Wait-WUServiceState -ServiceName $serviceName -DesiredState 'Running' -TimeoutSeconds 20)) {
                Write-Log "$serviceName running" -Level SUCCESS
            }
            else {
                Write-Log "Could not confirm $serviceName running: $($startOutput -join ' ')" -Level WARNING
            }
        }
    }
}

function Repair-DeliveryOptimization {
    Write-Log "DELIVERY OPTIMIZATION - Resetting Cache and Download Mode Policy" -Level SECTION

    $service = Get-Service -Name 'dosvc' -ErrorAction SilentlyContinue
    $wasRunning = ($service -and $service.Status -eq 'Running')

    if ($service -and $service.Status -eq 'Running') {
        Write-Log "Stopping dosvc with sc.exe..."
        $stopOutput = & sc.exe stop dosvc 2>&1
        if ($LASTEXITCODE -eq 0 -and (Wait-WUServiceState -ServiceName 'dosvc' -DesiredState 'Stopped' -TimeoutSeconds 20)) {
            Write-Log "dosvc stopped" -Level SUCCESS
        }
        else {
            Write-Log "Could not confirm dosvc stopped: $($stopOutput -join ' ')" -Level WARNING
        }
    }

    $cacheReset = $false
    if (Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        try {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log "Delivery Optimization cache cleared with Delete-DeliveryOptimizationCache" -Level SUCCESS
            $cacheReset = $true
        }
        catch {
            Write-Log "Delete-DeliveryOptimizationCache failed: $($_.Exception.Message)" -Level WARNING
        }
    }

    $cachePath = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
    if (-not $cacheReset) {
        if (Test-Path -LiteralPath $cachePath) {
            $backupPath = "$cachePath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            try {
                Move-Item -LiteralPath $cachePath -Destination $backupPath -Force -ErrorAction Stop
                Write-Log "Delivery Optimization cache moved to: $backupPath" -Level SUCCESS
            }
            catch {
                Write-Log "Could not move Delivery Optimization cache: $($_.Exception.Message)" -Level WARNING
                try {
                    Get-ChildItem -LiteralPath $cachePath -Force -ErrorAction Stop |
                        Remove-Item -Recurse -Force -ErrorAction Stop
                    Write-Log "Delivery Optimization cache contents removed" -Level SUCCESS
                }
                catch {
                    Write-Log "Could not clear Delivery Optimization cache contents: $($_.Exception.Message)" -Level WARNING
                }
            }
        }
        else {
            Write-Log "Delivery Optimization cache folder not found; it will be recreated" -Level INFO
        }

        try {
            New-Item -Path $cachePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Delivery Optimization cache folder ready" -Level SUCCESS
        }
        catch {
            Write-Log "Could not recreate Delivery Optimization cache folder: $($_.Exception.Message)" -Level WARNING
        }
    }

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    $modeValues = @('DODownloadMode', 'DeliveryOptimizationDownloadMode')
    foreach ($modeValue in $modeValues) {
        try {
            if (Test-Path -LiteralPath $policyPath) {
                $currentValue = Get-WURegistryValue -Path $policyPath -Name $modeValue
                if ($null -ne $currentValue) {
                    Remove-ItemProperty -LiteralPath $policyPath -Name $modeValue -Force -ErrorAction Stop
                    Write-Log "Removed Delivery Optimization policy value: $modeValue" -Level SUCCESS
                }
            }
        }
        catch {
            Write-Log "Could not remove Delivery Optimization policy value ${modeValue}: $($_.Exception.Message)" -Level WARNING
        }
    }

    if (-not (Test-Path -LiteralPath $policyPath)) {
        Write-Log "No Delivery Optimization policy key found" -Level SUCCESS
    }

    if ($service -and ($wasRunning -or $service.Status -ne 'Running')) {
        Write-Log "Starting dosvc with sc.exe..."
        $startOutput = & sc.exe start dosvc 2>&1
        if ($LASTEXITCODE -eq 0 -and (Wait-WUServiceState -ServiceName 'dosvc' -DesiredState 'Running' -TimeoutSeconds 20)) {
            Write-Log "dosvc running" -Level SUCCESS
        }
        else {
            Write-Log "Could not confirm dosvc running: $($startOutput -join ' ')" -Level WARNING
        }
    }
}

function Update-GroupPolicy {
    Write-Log "POLICY - Refreshing Group Policy" -Level SECTION

    Write-Log "Forcing Group Policy update..."
    $result = gpupdate /force 2>&1
    Write-Log "Group Policy refreshed" -Level SUCCESS
}

function Get-WUOperationResultName {
    param(
        [int]$ResultCode
    )

    switch ($ResultCode) {
        0 { return 'NotStarted' }
        1 { return 'InProgress' }
        2 { return 'Succeeded' }
        3 { return 'SucceededWithErrors' }
        4 { return 'Failed' }
        5 { return 'Aborted' }
        default { return "Unknown ($ResultCode)" }
    }
}

function Get-WUUpdateKbText {
    param(
        [object]$Update
    )

    try {
        $kbIds = @($Update.KBArticleIDs) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        if ($kbIds.Count -gt 0) {
            return (($kbIds | ForEach-Object { "KB$_" }) -join ', ')
        }
    }
    catch {
        Write-Log "Could not read update KB article IDs: $($_.Exception.Message)" -Level WARNING
    }

    return 'No KB listed'
}

function Get-WUUnsignedExitCode {
    param(
        [int]$ExitCode
    )

    return [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes([int]$ExitCode), 0)
}

function Format-WUExitCode {
    param(
        [int]$ExitCode
    )

    $unsigned = Get-WUUnsignedExitCode -ExitCode $ExitCode
    return ('0x{0:X8}' -f $unsigned)
}

function Test-WUExitCode {
    param(
        [int]$ExitCode,
        [uint32]$Expected
    )

    return ((Get-WUUnsignedExitCode -ExitCode $ExitCode) -eq $Expected)
}

function Convert-WUCatalogHtmlText {
    param(
        [string]$Html
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ''
    }

    $withoutTags = [regex]::Replace($Html, '<[^>]+>', ' ')
    $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
    return ([regex]::Replace($decoded, '\s+', ' ')).Trim()
}

function Get-WUCatalogProfile {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $currentVersion = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    $caption = if ($os -and $os.Caption) { [string]$os.Caption } else { 'Windows' }
    $product = if ($caption -match 'Windows 11') {
        'Windows 11'
    }
    elseif ($caption -match 'Windows 10') {
        'Windows 10'
    }
    else {
        $caption
    }

    $displayVersion = ''
    if ($currentVersion -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.DisplayVersion)) {
        $displayVersion = [string]$currentVersion.DisplayVersion
    }
    elseif ($currentVersion -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.ReleaseId)) {
        $displayVersion = [string]$currentVersion.ReleaseId
    }

    $processorArchitecture = [string]$env:PROCESSOR_ARCHITECTURE
    $architecture = if ($processorArchitecture -match 'ARM64') {
        'arm64'
    }
    elseif ($processorArchitecture -match '86' -and $processorArchitecture -notmatch 'AMD64') {
        'x86'
    }
    else {
        'x64'
    }

    $titleArchitecture = switch ($architecture) {
        'arm64' { 'arm64-based' }
        'x86' { 'x86-based' }
        default { 'x64-based' }
    }

    return [PSCustomObject]@{
        Caption           = $caption
        Product           = $product
        DisplayVersion    = $displayVersion
        BuildNumber       = if ($os) { [string]$os.BuildNumber } else { '' }
        Architecture      = $architecture
        TitleArchitecture = $titleArchitecture
    }
}

function Get-MicrosoftUpdateCatalogCellText {
    param(
        [string]$RowHtml,
        [string]$UpdateId,
        [int]$Column
    )

    $pattern = "(?is)<td[^>]+id=`"$([regex]::Escape($UpdateId))_C$Column`_R\d+`"[^>]*>(?<Text>.*?)</td>"
    $match = [regex]::Match($RowHtml, $pattern)
    if (-not $match.Success) {
        return ''
    }

    return Convert-WUCatalogHtmlText -Html $match.Groups['Text'].Value
}

function Search-MicrosoftUpdateCatalog {
    param(
        [string]$Query
    )

    $encodedQuery = [uri]::EscapeDataString($Query)
    $searchUri = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encodedQuery"
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $response = Invoke-WebRequest -Uri $searchUri -WebSession $session -UseBasicParsing -TimeoutSec 45 -ErrorAction Stop

    $results = @()
    $rowMatches = [regex]::Matches($response.Content, '(?is)<tr id="(?<Id>[0-9a-f-]{36})_R\d+"[^>]*>(?<Row>.*?)</tr>')
    foreach ($rowMatch in $rowMatches) {
        $updateId = $rowMatch.Groups['Id'].Value
        $rowHtml = $rowMatch.Groups['Row'].Value
        $titlePattern = "(?is)<a[^>]+id=['`"]$([regex]::Escape($updateId))_link['`"][^>]*>(?<Title>.*?)</a>"
        $titleMatch = [regex]::Match($rowHtml, $titlePattern)
        if (-not $titleMatch.Success) {
            continue
        }

        $dateText = Get-MicrosoftUpdateCatalogCellText -RowHtml $rowHtml -UpdateId $updateId -Column 4
        $published = [datetime]::MinValue
        [void][datetime]::TryParse($dateText, [ref]$published)

        $results += [PSCustomObject]@{
            UpdateId       = $updateId
            Title          = Convert-WUCatalogHtmlText -Html $titleMatch.Groups['Title'].Value
            Products       = Get-MicrosoftUpdateCatalogCellText -RowHtml $rowHtml -UpdateId $updateId -Column 2
            Classification = Get-MicrosoftUpdateCatalogCellText -RowHtml $rowHtml -UpdateId $updateId -Column 3
            Published      = $published
            Size           = Get-MicrosoftUpdateCatalogCellText -RowHtml $rowHtml -UpdateId $updateId -Column 6
            Query          = $Query
        }
    }

    return [PSCustomObject]@{
        SearchUri  = $searchUri
        WebSession = $session
        Results    = $results
    }
}

function Get-MicrosoftUpdateCatalogServicingStackSet {
    $catalogProfile = Get-WUCatalogProfile
    $queries = @()
    if (-not [string]::IsNullOrWhiteSpace($catalogProfile.DisplayVersion)) {
        $queries += "Servicing Stack Update $($catalogProfile.Product) Version $($catalogProfile.DisplayVersion) $($catalogProfile.Architecture)"
    }
    if (-not [string]::IsNullOrWhiteSpace($catalogProfile.BuildNumber)) {
        $queries += "Servicing Stack Update $($catalogProfile.Product) $($catalogProfile.BuildNumber) $($catalogProfile.Architecture)"
    }
    $queries += "Servicing Stack Update $($catalogProfile.Product) $($catalogProfile.Architecture)"

    foreach ($query in ($queries | Select-Object -Unique)) {
        Write-Log "Searching Microsoft Update Catalog: $query"
        try {
            $searchSet = Search-MicrosoftUpdateCatalog -Query $query
        }
        catch {
            Write-Log "Catalog search failed for '$query': $($_.Exception.Message)" -Level WARNING
            continue
        }

        $candidateMatches = @($searchSet.Results | Where-Object {
            $_.Title -match '(?i)Servicing Stack Update' -and
            $_.Title -match [regex]::Escape($catalogProfile.Product) -and
            $_.Title -match [regex]::Escape($catalogProfile.TitleArchitecture)
        })

        if (-not [string]::IsNullOrWhiteSpace($catalogProfile.DisplayVersion)) {
            $versionMatches = @($candidateMatches | Where-Object { $_.Title -match [regex]::Escape("Version $($catalogProfile.DisplayVersion)") })
            if ($versionMatches.Count -gt 0) {
                $candidateMatches = $versionMatches
            }
        }

        $candidateMatches = @($candidateMatches | Sort-Object Published, Title -Descending | Select-Object -First $Script:Config.CatalogMaxCandidates)
        if ($candidateMatches.Count -gt 0) {
            Write-Log "Catalog returned $($candidateMatches.Count) matching Servicing Stack candidate(s)" -Level SUCCESS
            return [PSCustomObject]@{
                SearchUri  = $searchSet.SearchUri
                WebSession = $searchSet.WebSession
                Profile    = $catalogProfile
                Candidates = $candidateMatches
            }
        }
    }

    Write-Log "No matching Servicing Stack Update was found in Microsoft Update Catalog" -Level WARNING
    return $null
}

function Get-MicrosoftUpdateCatalogDownloadUrl {
    param(
        [string]$UpdateId,
        [string]$SearchUri,
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession
    )

    $json = ConvertTo-Json -InputObject @([PSCustomObject]@{ updateID = $UpdateId }) -Compress
    $body = "updateIDs=$([uri]::EscapeDataString($json))"
    $headers = @{
        Referer        = $SearchUri
        'Content-Type' = 'application/x-www-form-urlencoded'
    }
    $response = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
        -Method Post `
        -Body $body `
        -Headers $headers `
        -WebSession $WebSession `
        -UseBasicParsing `
        -TimeoutSec 45 `
        -ErrorAction Stop

    $match = [regex]::Match($response.Content, "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'(?<Url>https://[^']+\.msu)'", 'IgnoreCase')
    if (-not $match.Success) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlDecode($match.Groups['Url'].Value)
}

function Invoke-MicrosoftUpdateCatalogDownload {
    param(
        [string]$Url
    )

    $downloadRoot = Join-Path $Script:Config.TempPath 'ServicingStack'
    New-Item -Path $downloadRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
    $fileName = [System.IO.Path]::GetFileName(([uri]$Url).LocalPath)
    $destination = Join-Path $downloadRoot $fileName

    Write-Log "Downloading Catalog SSU package: $fileName"
    Invoke-WebRequest -Uri $Url -OutFile $destination -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
    return $destination
}

function Invoke-ServicingStackMsuInstall {
    param(
        [string]$MsuPath
    )

    Write-Log "Installing SSU package with wusa.exe: $MsuPath"
    $process = Start-Process -FilePath 'wusa.exe' `
        -ArgumentList @("`"$MsuPath`"", '/quiet', '/norestart') `
        -Wait `
        -PassThru `
        -WindowStyle Hidden

    $exitCode = [int]$process.ExitCode
    $exitHex = Format-WUExitCode -ExitCode $exitCode
    if ($exitCode -eq 0) {
        Write-Log "wusa.exe install completed successfully ($exitHex)" -Level SUCCESS
        return 'Succeeded'
    }
    if ($exitCode -eq 3010) {
        Write-Log "wusa.exe install succeeded and requested reboot ($exitHex)" -Level WARNING
        return 'RebootRequired'
    }
    if ((Get-WUUnsignedExitCode -ExitCode $exitCode) -eq 0x00240006) {
        Write-Log "SSU package is already installed ($exitHex)" -Level SUCCESS
        return 'AlreadyInstalled'
    }
    if (Test-WUExitCode -ExitCode $exitCode -Expected 0x800f0922) {
        Write-Log "wusa.exe returned 0x800f0922 for this SSU package" -Level WARNING
        return 'ServicingStackFailure'
    }

    Write-Log "wusa.exe install failed with exit code $exitHex" -Level WARNING
    return 'Failed'
}

function Invoke-ServicingStackCatalogRepair {
    param(
        [string]$Reason = 'Servicing Stack Catalog repair requested'
    )

    Write-Log "SERVICING STACK - Microsoft Update Catalog Repair" -Level SECTION
    Write-Log $Reason

    $catalogSet = Get-MicrosoftUpdateCatalogServicingStackSet
    if ($null -eq $catalogSet) {
        return
    }

    foreach ($candidate in $catalogSet.Candidates) {
        Write-Log "Catalog candidate: $($candidate.Title) | Published: $($candidate.Published.ToString('yyyy-MM-dd')) | Size: $($candidate.Size)" -Level INFO

        try {
            $downloadUrl = Get-MicrosoftUpdateCatalogDownloadUrl -UpdateId $candidate.UpdateId -SearchUri $catalogSet.SearchUri -WebSession $catalogSet.WebSession
        }
        catch {
            Write-Log "Could not resolve Catalog download URL: $($_.Exception.Message)" -Level WARNING
            continue
        }

        if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
            Write-Log "Catalog did not return an MSU download URL for candidate $($candidate.UpdateId)" -Level WARNING
            continue
        }

        try {
            $packagePath = Invoke-MicrosoftUpdateCatalogDownload -Url $downloadUrl
        }
        catch {
            Write-Log "Could not download Catalog SSU package: $($_.Exception.Message)" -Level WARNING
            continue
        }

        $installState = Invoke-ServicingStackMsuInstall -MsuPath $packagePath
        if ($installState -in @('Succeeded', 'RebootRequired', 'AlreadyInstalled')) {
            Write-Log "Catalog Servicing Stack repair completed with state: $installState" -Level SUCCESS
            return
        }
        if ($installState -eq 'ServicingStackFailure') {
            Write-Log "Trying next Catalog SSU candidate after 0x800f0922" -Level WARNING
            continue
        }
    }

    Write-Log "Catalog Servicing Stack repair did not complete successfully" -Level WARNING
}

function Invoke-ServicingStackPreflight {
    Write-Log "SERVICING STACK - Staging Latest Applicable SSU" -Level SECTION

    try {
        $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        Write-Log "Searching Windows Update Agent for applicable Servicing Stack updates..."
        $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    }
    catch {
        Write-Log "Could not query Windows Update Agent for Servicing Stack updates: $($_.Exception.Message)" -Level WARNING
        return
    }

    $servicingUpdates = @()
    for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
        $update = $searchResult.Updates.Item($i)
        $title = [string]$update.Title
        if ($title -notmatch '(?i)\b(servicing stack|servicing stack update|ssu)\b') {
            continue
        }

        $lastDeployment = [datetime]::MinValue
        try {
            if ($null -ne $update.LastDeploymentChangeTime) {
                $lastDeployment = [datetime]$update.LastDeploymentChangeTime
            }
        }
        catch {
            Write-Log "Could not read SSU deployment date for '$title': $($_.Exception.Message)" -Level WARNING
        }

        $servicingUpdates += [PSCustomObject]@{
            Update                   = $update
            Title                    = $title
            KBText                   = Get-WUUpdateKbText -Update $update
            LastDeploymentChangeTime = $lastDeployment
            IsDownloaded             = [bool]$update.IsDownloaded
        }
    }

    if ($servicingUpdates.Count -eq 0) {
        Write-Log "No applicable Servicing Stack Update was offered by Windows Update Agent" -Level SUCCESS
        return
    }

    $selected = $servicingUpdates | Sort-Object LastDeploymentChangeTime, Title -Descending | Select-Object -First 1
    if ($servicingUpdates.Count -gt 1) {
        Write-Log "Found $($servicingUpdates.Count) applicable Servicing Stack updates; selecting the latest deployment date" -Level INFO
    }
    Write-Log "Selected SSU: $($selected.Title) ($($selected.KBText))" -Level INFO

    try {
        if ($selected.Update.EulaAccepted -eq $false) {
            $selected.Update.AcceptEula()
            Write-Log "Accepted SSU EULA through Windows Update Agent" -Level INFO
        }
    }
    catch {
        Write-Log "Could not accept SSU EULA: $($_.Exception.Message)" -Level WARNING
    }

    try {
        $updatesToProcess = New-Object -ComObject Microsoft.Update.UpdateColl -ErrorAction Stop
        [void]$updatesToProcess.Add($selected.Update)
    }
    catch {
        Write-Log "Could not create Windows Update collection for SSU staging: $($_.Exception.Message)" -Level WARNING
        return
    }

    if (-not $selected.Update.IsDownloaded) {
        try {
            Write-Log "Downloading selected SSU through Windows Update Agent..."
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $updatesToProcess
            $downloadResult = $downloader.Download()
            $downloadStatus = Get-WUOperationResultName -ResultCode ([int]$downloadResult.ResultCode)
            if ([int]$downloadResult.ResultCode -in @(2, 3)) {
                Write-Log "SSU download result: $downloadStatus" -Level SUCCESS
            }
            else {
                Write-Log "SSU download result: $downloadStatus" -Level WARNING
                return
            }
        }
        catch {
            Write-Log "Could not download selected SSU: $($_.Exception.Message)" -Level WARNING
            return
        }
    }
    else {
        Write-Log "Selected SSU is already downloaded in the Windows Update cache" -Level SUCCESS
    }

    try {
        Write-Log "Installing selected SSU before DISM RestoreHealth..."
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updatesToProcess
        $installer.AllowSourcePrompts = $false
        $installer.ForceQuiet = $true
        $installResult = $installer.Install()
        $installStatus = Get-WUOperationResultName -ResultCode ([int]$installResult.ResultCode)

        if ([int]$installResult.ResultCode -eq 2) {
            Write-Log "SSU install result: $installStatus" -Level SUCCESS
        }
        elseif ([int]$installResult.ResultCode -eq 3) {
            Write-Log "SSU install result: $installStatus" -Level WARNING
        }
        else {
            Write-Log "SSU install result: $installStatus" -Level WARNING
        }

        if ($installResult.RebootRequired) {
            Write-Log "SSU installation requested a restart; DISM will continue, but reboot after repair is important" -Level WARNING
        }

        try {
            $updateResult = $installResult.GetUpdateResult(0)
            $hresult = [int]$updateResult.HResult
            if ($hresult -ne 0) {
                $hresultHex = Format-WUExitCode -ExitCode $hresult
                Write-Log "SSU install HRESULT: $hresultHex" -Level WARNING
                if (Test-WUExitCode -ExitCode $hresult -Expected 0x800f0922) {
                    Invoke-ServicingStackCatalogRepair -Reason 'Windows Update Agent returned 0x800f0922 while staging SSU; falling back to Microsoft Update Catalog.'
                }
            }
        }
        catch {
            Write-Log "Could not read SSU install HRESULT: $($_.Exception.Message)" -Level WARNING
        }
    }
    catch {
        Write-Log "Could not install selected SSU: $($_.Exception.Message)" -Level WARNING
    }
}

function Convert-WUSizeToMegabyte {
    param(
        [string]$SizeText
    )

    if ([string]::IsNullOrWhiteSpace($SizeText)) {
        return 0
    }

    $normalized = $SizeText.Trim()
    if ($normalized -notmatch '(?<Value>[\d\.,]+)\s*(?<Unit>bytes?|KB|MB|GB|TB)') {
        return 0
    }

    $numberText = $Matches.Value
    if ($numberText.Contains(',') -and $numberText.Contains('.')) {
        $numberText = $numberText.Replace(',', '')
    }
    elseif ($numberText.Contains(',')) {
        $numberText = $numberText.Replace(',', '.')
    }

    $number = 0.0
    if (-not [double]::TryParse($numberText, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return 0
    }

    switch ($Matches.Unit.ToUpperInvariant()) {
        'BYTE' { return [math]::Round($number / 1MB, 2) }
        'BYTES' { return [math]::Round($number / 1MB, 2) }
        'KB' { return [math]::Round($number / 1024, 2) }
        'MB' { return [math]::Round($number, 2) }
        'GB' { return [math]::Round($number * 1024, 2) }
        'TB' { return [math]::Round($number * 1024 * 1024, 2) }
        default { return 0 }
    }
}

function Get-ComponentStoreAnalysis {
    Write-Log "Analyzing component store with DISM /AnalyzeComponentStore..."

    $analysisOutput = DISM /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $analysisExitCode = $LASTEXITCODE
    if ($analysisExitCode -ne 0) {
        Write-Log "AnalyzeComponentStore failed with exit code $analysisExitCode" -Level WARNING
        return $null
    }

    $analysis = [ordered]@{
        ExplorerReportedSizeMB      = 0
        ActualSizeMB                = 0
        SharedWithWindowsMB         = 0
        BackupsDisabledFeaturesMB   = 0
        CacheTemporaryDataMB        = 0
        CleanupDeltaMB              = 0
        ExplorerActualDeltaMB       = 0
        ReclaimablePackages         = 0
        CleanupRecommended          = $false
        RawOutput                   = ($analysisOutput -join "`n")
    }

    foreach ($line in $analysisOutput) {
        $text = [string]$line
        if ($text -match 'Windows Explorer Reported Size of Component Store\s*:\s*(?<Size>.+)$') {
            $analysis.ExplorerReportedSizeMB = Convert-WUSizeToMegabyte -SizeText $Matches.Size
        }
        elseif ($text -match 'Actual Size of Component Store\s*:\s*(?<Size>.+)$') {
            $analysis.ActualSizeMB = Convert-WUSizeToMegabyte -SizeText $Matches.Size
        }
        elseif ($text -match 'Shared with Windows\s*:\s*(?<Size>.+)$') {
            $analysis.SharedWithWindowsMB = Convert-WUSizeToMegabyte -SizeText $Matches.Size
        }
        elseif ($text -match 'Backups and Disabled Features\s*:\s*(?<Size>.+)$') {
            $analysis.BackupsDisabledFeaturesMB = Convert-WUSizeToMegabyte -SizeText $Matches.Size
        }
        elseif ($text -match 'Cache and Temporary Data\s*:\s*(?<Size>.+)$') {
            $analysis.CacheTemporaryDataMB = Convert-WUSizeToMegabyte -SizeText $Matches.Size
        }
        elseif ($text -match 'Number of Reclaimable Packages\s*:\s*(?<Count>\d+)') {
            $analysis.ReclaimablePackages = [int]$Matches.Count
        }
        elseif ($text -match 'Component Store Cleanup Recommended\s*:\s*(?<Value>Yes|No)') {
            $analysis.CleanupRecommended = ($Matches.Value -eq 'Yes')
        }
    }

    $analysis.CleanupDeltaMB = [math]::Round(($analysis.BackupsDisabledFeaturesMB + $analysis.CacheTemporaryDataMB), 2)
    if ($analysis.ExplorerReportedSizeMB -gt $analysis.ActualSizeMB) {
        $analysis.ExplorerActualDeltaMB = [math]::Round(($analysis.ExplorerReportedSizeMB - $analysis.ActualSizeMB), 2)
    }

    return [PSCustomObject]$analysis
}

function Invoke-ComponentStoreCleanup {
    $analysis = Get-ComponentStoreAnalysis
    $thresholdMB = [double]$Script:Config.ComponentStoreResetBaseThresholdMB
    $useResetBase = $false

    if ($null -ne $analysis) {
        Write-Log ("Component store sizes: Explorer={0} MB, Actual={1} MB, Shared={2} MB" -f $analysis.ExplorerReportedSizeMB, $analysis.ActualSizeMB, $analysis.SharedWithWindowsMB) -Level INFO
        Write-Log ("Component store cleanup delta: {0} MB; Reclaimable packages: {1}; Cleanup recommended: {2}" -f $analysis.CleanupDeltaMB, $analysis.ReclaimablePackages, $analysis.CleanupRecommended) -Level INFO
        if ($analysis.ExplorerActualDeltaMB -gt 0) {
            Write-Log ("Explorer vs actual component-store delta: {0} MB" -f $analysis.ExplorerActualDeltaMB) -Level INFO
        }

        $useResetBase = ($analysis.CleanupRecommended -and $analysis.CleanupDeltaMB -ge $thresholdMB)
        if ($useResetBase) {
            Write-Log "Cleanup delta meets /ResetBase threshold ($thresholdMB MB); superseded updates will no longer be uninstallable" -Level WARNING
        }
        else {
            Write-Log "Cleanup delta is below /ResetBase threshold ($thresholdMB MB); using standard StartComponentCleanup" -Level INFO
        }
    }
    else {
        Write-Log "Component store analysis unavailable; using standard StartComponentCleanup" -Level WARNING
    }

    if ($useResetBase) {
        Write-Log "Running StartComponentCleanup /ResetBase..."
        $resetOutput = DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Component cleanup with /ResetBase complete" -Level SUCCESS
            return
        }

        Write-Log "StartComponentCleanup /ResetBase failed: $($resetOutput -join ' ')" -Level WARNING
        Write-Log "Falling back to standard StartComponentCleanup..."
    }
    else {
        Write-Log "Running standard StartComponentCleanup..."
    }

    $cleanupOutput = DISM /Online /Cleanup-Image /StartComponentCleanup 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Component cleanup complete" -Level SUCCESS
    }
    else {
        Write-Log "StartComponentCleanup completed with issues: $($cleanupOutput -join ' ')" -Level WARNING
    }
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

    Invoke-ComponentStoreCleanup
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
        @{ Key = 'WaaSMedicStatus'; Label = 'WaaSMedic service' },
        @{ Key = 'UpdateHealthToolsStatus'; Label = 'Update Health Tools' },
        @{ Key = 'UpdateHealthServiceStatus'; Label = 'Update Health service' },
        @{ Key = 'RemediationServiceStatus'; Label = 'Remediation service' },
        @{ Key = 'WSUSPostureSummary'; Label = 'WSUS / SUP posture' },
        @{ Key = 'UseWUServer'; Label = 'UseWUServer' },
        @{ Key = 'DualScanPolicy'; Label = 'Dual scan policy' },
        @{ Key = 'DeliveryOptimizationMode'; Label = 'DO download mode' },
        @{ Key = 'DeliveryOptimizationPeerCache'; Label = 'DO peer cache' },
        @{ Key = 'SoftwareDistribution'; Label = 'SoftwareDistribution' },
        @{ Key = 'Catroot2'; Label = 'catroot2' },
        @{ Key = 'DISMHealth'; Label = 'DISM health' },
        @{ Key = 'PendingReboot'; Label = 'Pending reboot' },
        @{ Key = 'PendingXml'; Label = 'pending.xml' },
        @{ Key = 'LastSuccessfulUpdate'; Label = 'Last successful update' },
        @{ Key = 'TopWUError'; Label = 'Top WU HRESULT' }
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

function Get-DiagnosticReportDelta {
    param(
        [hashtable]$Before,
        [hashtable]$After
    )

    $serviceChanges = @()
    $beforeServices = @($Before['Services'])
    $afterServices = @($After['Services'])
    foreach ($beforeService in $beforeServices) {
        $afterService = $afterServices | Where-Object { $_.Component -eq $beforeService.Component } | Select-Object -First 1
        if ($afterService -and [string]$beforeService.Status -ne [string]$afterService.Status) {
            $serviceChanges += [PSCustomObject]@{
                Component = [string]$beforeService.Component
                Before    = [string]$beforeService.Status
                After     = [string]$afterService.Status
            }
        }
    }

    $changedFields = @()
    $keys = (@($Before.Keys) + @($After.Keys)) | Sort-Object -Unique
    foreach ($key in $keys) {
        if ($key -eq 'Services') {
            continue
        }

        $beforeValue = if ($Before.ContainsKey($key)) { [string]$Before[$key] } else { $null }
        $afterValue = if ($After.ContainsKey($key)) { [string]$After[$key] } else { $null }
        if ($beforeValue -ne $afterValue) {
            $changedFields += [PSCustomObject]@{
                Key    = [string]$key
                Before = $beforeValue
                After  = $afterValue
            }
        }
    }

    return [PSCustomObject]@{
        ServiceChanges = $serviceChanges
        ChangedFields  = $changedFields
    }
}

function Write-JsonRepairReport {
    param(
        [string]$Path,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [timespan]$Duration,
        [string]$ModeLabel,
        [bool]$SelectiveMode,
        [hashtable]$PreReport,
        [hashtable]$PostReport,
        [bool]$PostConnectivity,
        [array]$PhaseResults,
        [hashtable]$Options
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $parent = Split-Path -Path $resolvedPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $reportObject = [ordered]@{
            SchemaVersion          = '1.0'
            Tool                   = 'WURepair'
            Version                = $Script:Config.Version
            StartedAt              = $StartTime.ToString('o')
            EndedAt                = $EndTime.ToString('o')
            DurationSeconds        = [math]::Round($Duration.TotalSeconds, 2)
            Mode                   = $ModeLabel
            SelectiveMode          = $SelectiveMode
            Options                = $Options
            LogPath                = $Script:Config.LogPath
            PostRepairConnectivity = if ($PostConnectivity) { 'AllEndpointsReachable' } else { 'SomeEndpointsUnreachable' }
            PhaseResults           = $PhaseResults
            Delta                  = Get-DiagnosticReportDelta -Before $PreReport -After $PostReport
            PreRepair              = $PreReport
            PostRepair             = $PostReport
        }

        $json = $reportObject | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $resolvedPath -Value $json -Encoding UTF8 -Force
        Write-Log "JSON report written to: $resolvedPath" -Level SUCCESS
    }
    catch {
        Write-Log "Could not write JSON report '$Path': $($_.Exception.Message)" -Level WARNING
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
        [switch]$RepairWaaS,
        [switch]$RepairDelivery,
        [switch]$RepairServicingStack,
        [switch]$StageSSU,
        [switch]$RepairAll,
        [string]$JsonReport
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
    $selectiveMode = ($RepairServices -or $RepairDLLs -or $RepairStore -or $RepairDISM -or $RepairSFC -or $RepairNetwork -or $RepairWaaS -or $RepairDelivery -or $RepairServicingStack)
    if ($RepairAll -or (-not $selectiveMode)) {
        # Full repair mode
        $RepairServices = $true
        $RepairDLLs     = $true
        $RepairStore    = $true
        $RepairDISM     = $true
        $RepairSFC      = $true
        $RepairNetwork  = $true
        $RepairWaaS     = $true
        $RepairDelivery = $true
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
        if ($RepairDISM) {
            if ($StageSSU) {
                $plannedSteps += 'Stage the latest applicable Servicing Stack Update before DISM.'
            }
            $plannedSteps += 'Run DISM to inspect and repair the component store.'
        }
        elseif ($StageSSU) {
            $plannedSteps += 'SSU staging was requested, but it will be skipped because DISM is not running.'
        }
        if ($RepairSFC) { $plannedSteps += 'Run System File Checker to repair protected Windows files.' }
        if ($RepairNetwork) { $plannedSteps += 'Reset Winsock and key network update paths.' }
        if ($RepairWaaS) { $plannedSteps += 'Reset Update Orchestrator services and re-enable USO scheduled tasks.' }
        if ($RepairDelivery) { $plannedSteps += 'Reset Delivery Optimization cache and download-mode policy.' }
        if ($RepairServicingStack) { $plannedSteps += 'Repair the Servicing Stack by downloading and installing a matching Microsoft Update Catalog SSU.' }
        if (-not [string]::IsNullOrWhiteSpace($JsonReport)) { $plannedSteps += "Write machine-parseable JSON repair report to $JsonReport." }
    }
    else {
        $plannedSteps += @(
            'Clean Microsoft update blocks from the hosts file and restore key TLS settings.'
            'Repair firewall rules, service dependencies, and Windows Update blocking policies.'
            'Stop update-related services, refresh their configuration, and rebuild update caches.'
            'Re-register update DLLs, reset network and Delivery Optimization components, clean registry state, and refresh Update Orchestrator.'
        )
        if ($RepairDISM -and $StageSSU) { $plannedSteps += 'Stage the latest applicable Servicing Stack Update before DISM.' }
        elseif ($StageSSU) { $plannedSteps += 'SSU staging was requested, but it will be skipped because DISM is not running.' }
        if ($RepairServicingStack) { $plannedSteps += 'Repair the Servicing Stack by downloading and installing a matching Microsoft Update Catalog SSU.' }
        if ($RepairDISM) { $plannedSteps += 'Run DISM repairs to heal the Windows component store.' }
        if ($RepairSFC) { $plannedSteps += 'Run System File Checker to validate and repair protected files.' }
        if (-not [string]::IsNullOrWhiteSpace($JsonReport)) { $plannedSteps += "Write machine-parseable JSON repair report to $JsonReport." }
    }

    $estimatedDuration = Get-EstimatedRepairDuration -SelectiveMode $selectiveMode -RepairDISM $RepairDISM -RepairSFC $RepairSFC -RepairNetwork $RepairNetwork -RepairStore $RepairStore -RepairWaaS $RepairWaaS -RepairDelivery $RepairDelivery -RepairServicingStack $RepairServicingStack -StageSSU $StageSSU
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
    if (-not [string]::IsNullOrWhiteSpace($JsonReport)) {
        Write-UiMetric -Label 'JSON report' -Value $JsonReport -Tone 'Info'
    }

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
    if ($RepairDelivery) {
        $phases += @{ Name = 'Reset Delivery Optimization'; Action = { Repair-DeliveryOptimization } }
    }
    if ($RepairWaaS) {
        $phases += @{ Name = 'Reset WaaS Orchestrator';    Action = { Repair-WaaSOrchestrator } }
    }
    if ($RepairDISM -and $StageSSU) {
        $phases += @{ Name = 'Stage Servicing Stack';       Action = { Invoke-ServicingStackPreflight } }
    }
    if ($RepairServicingStack) {
        $phases += @{ Name = 'Repair Servicing Stack';      Action = { Invoke-ServicingStackCatalogRepair } }
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
    $phaseResults = @()

    foreach ($phase in $phases) {
        $currentPhase++
        $pct = [int](($currentPhase / $totalPhases) * 100)
        $phaseStart = Get-Date
        Write-Progress -Activity "WURepair v$($Script:Config.Version)" `
            -Status "Phase $currentPhase of $totalPhases : $($phase.Name)" `
            -PercentComplete $pct
        Write-Log "--- Phase $currentPhase of $totalPhases : $($phase.Name) ---"
        & $phase.Action
        $phaseEnd = Get-Date
        $phaseResults += [PSCustomObject]@{
            Index           = $currentPhase
            Name            = $phase.Name
            Status          = 'Completed'
            StartedAt       = $phaseStart.ToString('o')
            EndedAt         = $phaseEnd.ToString('o')
            DurationSeconds = [math]::Round(($phaseEnd - $phaseStart).TotalSeconds, 2)
        }
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

    $reportOptions = @{
        QuickMode             = [bool]$QuickMode
        SkipDISM              = [bool]$SkipDISM
        SkipSFC               = [bool]$SkipSFC
        SkipBackup            = [bool]$SkipBackup
        RepairServices        = [bool]$RepairServices
        RepairDLLs            = [bool]$RepairDLLs
        RepairStore           = [bool]$RepairStore
        RepairDISM            = [bool]$RepairDISM
        RepairSFC             = [bool]$RepairSFC
        RepairNetwork         = [bool]$RepairNetwork
        RepairWaaS            = [bool]$RepairWaaS
        RepairDelivery        = [bool]$RepairDelivery
        RepairServicingStack  = [bool]$RepairServicingStack
        StageSSU              = [bool]$StageSSU
        RepairAll             = [bool]$RepairAll
    }
    Write-JsonRepairReport -Path $JsonReport -StartTime $startTime -EndTime $endTime -Duration $duration -ModeLabel $modeLabel -SelectiveMode $selectiveMode -PreReport $preReport -PostReport $postReport -PostConnectivity $postConnectivity -PhaseResults $phaseResults -Options $reportOptions

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
        '-StageSSU             Download/install an applicable Servicing Stack Update before DISM.',
        '-JsonReport <path>    Write pre/post diagnostic delta as JSON for RMM ingestion.',
        '-Help                 Show this help screen.'
    )

    Write-UiList -Title 'Targeted repair switches' -Items @(
        '-RepairServices  Reset and restart Windows Update services.',
        '-RepairDLLs      Re-register Windows Update DLLs.',
        '-RepairStore     Rebuild SoftwareDistribution and catroot2.',
        '-RepairDISM      Run DISM component store repair only.',
        '-RepairSFC       Run System File Checker only.',
        '-RepairNetwork   Reset network stack and update connectivity paths.',
        '-RepairWaaS      Reset Update Orchestrator services and USO tasks.',
        '-RepairDelivery  Reset Delivery Optimization cache and download mode.',
        '-RepairServicingStack  Download/install matching Catalog SSU package.',
        '-RepairAll       Force the full repair flow.'
    )

    Write-UiList -Title 'Examples' -Items @(
        '.\WURepair.ps1',
        '.\WURepair.ps1 -Quick',
        '.\WURepair.ps1 -RepairServices',
        '.\WURepair.ps1 -RepairStore -RepairDLLs',
        '.\WURepair.ps1 -RepairDISM -StageSSU',
        '.\WURepair.ps1 -JsonReport C:\Temp\WURepair-report.json',
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

function Get-CommandLineOptionValue {
    param(
        [string[]]$Arguments,
        [string]$Name
    )

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $argument = [string]$Arguments[$i]
        if ($argument -like "$Name=*") {
            return $argument.Substring($Name.Length + 1)
        }
        if ($argument -eq $Name) {
            if ($i + 1 -ge $Arguments.Count -or [string]$Arguments[$i + 1] -like '-*') {
                throw "$Name requires a path value."
            }
            return [string]$Arguments[$i + 1]
        }
    }

    return $null
}

$params = @{}

if ($args -contains '-SkipDISM') { $params['SkipDISM'] = $true }
if ($args -contains '-SkipSFC') { $params['SkipSFC'] = $true }
if ($args -contains '-SkipBackup') { $params['SkipBackup'] = $true }
if ($args -contains '-StageSSU' -or $args -contains '-StageServicingStack') { $params['StageSSU'] = $true }
if ($args -contains '-QuickMode' -or $args -contains '-Quick') { $params['QuickMode'] = $true }
if ($args -contains '-RepairServices') { $params['RepairServices'] = $true }
if ($args -contains '-RepairDLLs') { $params['RepairDLLs'] = $true }
if ($args -contains '-RepairStore') { $params['RepairStore'] = $true }
if ($args -contains '-RepairDISM') { $params['RepairDISM'] = $true }
if ($args -contains '-RepairSFC') { $params['RepairSFC'] = $true }
if ($args -contains '-RepairNetwork') { $params['RepairNetwork'] = $true }
if ($args -contains '-RepairWaaS') { $params['RepairWaaS'] = $true }
if ($args -contains '-RepairDelivery') { $params['RepairDelivery'] = $true }
if ($args -contains '-RepairServicingStack') { $params['RepairServicingStack'] = $true }
if ($args -contains '-RepairAll') { $params['RepairAll'] = $true }

$jsonReportPath = Get-CommandLineOptionValue -Arguments $args -Name '-JsonReport'
if (-not [string]::IsNullOrWhiteSpace($jsonReportPath)) { $params['JsonReport'] = $jsonReportPath }

if ($args -contains '-Help' -or $args -contains '-?') {
    Show-Help
    exit
}

# Run the repair
Start-WURepair @params
