Set-StrictMode -Version 2.0

function Get-WURepairScriptPath {
    $moduleRoot = $PSScriptRoot
    $scriptPath = Join-Path $moduleRoot 'WURepair.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "WURepair.ps1 was not found next to the module wrapper: $scriptPath"
    }

    return $scriptPath
}

function Add-WURepairSwitchArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [bool]$Enabled
    )

    if ($Enabled) {
        [void]$Arguments.Add($Name)
    }
}

function Add-WURepairValueArgument {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [string]$Name,
        [AllowNull()][string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        [void]$Arguments.Add($Name)
        [void]$Arguments.Add($Value)
    }
}

function Invoke-WURepairScript {
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @()
    )

    $scriptPath = Get-WURepairScriptPath
    $powerShellExe = (Get-Command -Name powershell.exe -ErrorAction Stop).Source
    & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
    return $LASTEXITCODE
}

function Invoke-WURepair {
    [CmdletBinding()]
    param(
        [switch]$Quick,
        [switch]$SkipDISM,
        [switch]$SkipSFC,
        [switch]$SkipBackup,
        [switch]$StageSSU,
        [switch]$RepairServices,
        [switch]$RepairDLLs,
        [switch]$RepairStore,
        [switch]$RepairDISM,
        [switch]$RepairSFC,
        [switch]$RepairNetwork,
        [switch]$RepairWaaS,
        [switch]$RepairDelivery,
        [switch]$RepairServicingStack,
        [switch]$RepairAll,
        [switch]$AnalyzeLogs,
        [string]$DismSource,
        [switch]$DismLimitAccess,
        [string]$JsonReport,
        [string]$SupportBundle,
        [string]$JournalPath,
        [string]$RollbackJournal,
        [switch]$ApplyRollback,
        [switch]$ResetManagedUpdatePolicy,
        [switch]$OverrideReadinessBlock,
        [switch]$NoRedact,
        [switch]$PlainText,
        [switch]$Unattended
    )

    $arguments = New-Object 'System.Collections.Generic.List[string]'
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-Quick' -Enabled ([bool]$Quick)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-SkipDISM' -Enabled ([bool]$SkipDISM)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-SkipSFC' -Enabled ([bool]$SkipSFC)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-SkipBackup' -Enabled ([bool]$SkipBackup)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-StageSSU' -Enabled ([bool]$StageSSU)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairServices' -Enabled ([bool]$RepairServices)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairDLLs' -Enabled ([bool]$RepairDLLs)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairStore' -Enabled ([bool]$RepairStore)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairDISM' -Enabled ([bool]$RepairDISM)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairSFC' -Enabled ([bool]$RepairSFC)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairNetwork' -Enabled ([bool]$RepairNetwork)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairWaaS' -Enabled ([bool]$RepairWaaS)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairDelivery' -Enabled ([bool]$RepairDelivery)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairServicingStack' -Enabled ([bool]$RepairServicingStack)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-RepairAll' -Enabled ([bool]$RepairAll)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-AnalyzeLogs' -Enabled ([bool]$AnalyzeLogs)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-DismLimitAccess' -Enabled ([bool]$DismLimitAccess)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-ApplyRollback' -Enabled ([bool]$ApplyRollback)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-ResetManagedUpdatePolicy' -Enabled ([bool]$ResetManagedUpdatePolicy)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-OverrideReadinessBlock' -Enabled ([bool]$OverrideReadinessBlock)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-NoRedact' -Enabled ([bool]$NoRedact)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-PlainText' -Enabled ([bool]$PlainText)
    Add-WURepairSwitchArgument -Arguments $arguments -Name '-Unattended' -Enabled ([bool]$Unattended)

    Add-WURepairValueArgument -Arguments $arguments -Name '-DismSource' -Value $DismSource
    Add-WURepairValueArgument -Arguments $arguments -Name '-JsonReport' -Value $JsonReport
    Add-WURepairValueArgument -Arguments $arguments -Name '-SupportBundle' -Value $SupportBundle
    Add-WURepairValueArgument -Arguments $arguments -Name '-JournalPath' -Value $JournalPath
    Add-WURepairValueArgument -Arguments $arguments -Name '-RollbackJournal' -Value $RollbackJournal

    return Invoke-WURepairScript -Arguments $arguments.ToArray()
}

function Invoke-WURepairPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PhaseSwitch,
        [switch]$Unattended,
        [switch]$PlainText,
        [string]$JsonReport,
        [string]$SupportBundle,
        [switch]$AnalyzeLogs,
        [switch]$NoRedact
    )

    $parameters = @{
        Unattended = [bool]$Unattended
        PlainText = [bool]$PlainText
        AnalyzeLogs = [bool]$AnalyzeLogs
        NoRedact = [bool]$NoRedact
    }
    if (-not [string]::IsNullOrWhiteSpace($JsonReport)) { $parameters.JsonReport = $JsonReport }
    if (-not [string]::IsNullOrWhiteSpace($SupportBundle)) { $parameters.SupportBundle = $SupportBundle }
    $parameters[$PhaseSwitch] = $true

    return Invoke-WURepair @parameters
}

function Repair-WURepairServices {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairServices' @PSBoundParameters
}

function Repair-WURepairDlls {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairDLLs' @PSBoundParameters
}

function Repair-WURepairStore {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairStore' @PSBoundParameters
}

function Repair-WURepairDism {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact, [string]$DismSource, [switch]$DismLimitAccess)

    $parameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        $parameters[$key] = $PSBoundParameters[$key]
    }
    $parameters.RepairDISM = $true
    Invoke-WURepair @parameters
}

function Repair-WURepairSfc {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairSFC' @PSBoundParameters
}

function Repair-WURepairNetwork {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairNetwork' @PSBoundParameters
}

function Repair-WURepairWaaS {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairWaaS' @PSBoundParameters
}

function Repair-WURepairDelivery {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairDelivery' @PSBoundParameters
}

function Repair-WURepairServicingStack {
    [CmdletBinding()]
    param([switch]$Unattended, [switch]$PlainText, [string]$JsonReport, [string]$SupportBundle, [switch]$AnalyzeLogs, [switch]$NoRedact)
    Invoke-WURepairPhase -PhaseSwitch 'RepairServicingStack' @PSBoundParameters
}

Export-ModuleMember -Function @(
    'Invoke-WURepair',
    'Repair-WURepairServices',
    'Repair-WURepairDlls',
    'Repair-WURepairStore',
    'Repair-WURepairDism',
    'Repair-WURepairSfc',
    'Repair-WURepairNetwork',
    'Repair-WURepairWaaS',
    'Repair-WURepairDelivery',
    'Repair-WURepairServicingStack'
)
