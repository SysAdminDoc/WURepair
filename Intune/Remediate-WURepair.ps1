<#
.SYNOPSIS
    Intune Proactive Remediation - Remediation Script for Windows Update repair.
.DESCRIPTION
    Runs a comprehensive Windows Update repair using WURepair.ps1 in unattended
    mode with JSON reporting. Designed for Intune proactive remediation pairing
    with Detect-WURepair.ps1.

    Exit 0 = Repair succeeded (or completed with warnings).
    Exit 1 = Repair failed or script not found.

    JSON report and mutation journal are written to the local temp folder for
    RMM collection or support escalation.

    Designed for 64-bit PowerShell 5.1 hosting in Intune proactive remediations.
.NOTES
    Part of WURepair. Upload this as the remediation script in Intune.
    Pair with Detect-WURepair.ps1 as the detection script.

    WURepair.ps1 must be deployed to a known path on managed devices.
    Set $WURepairScriptPath below to match your deployment location.
#>

$ErrorActionPreference = 'Stop'

$candidatePaths = @(
    "$env:ProgramData\WURepair\WURepair.ps1",
    "$env:ProgramFiles\WURepair\WURepair.ps1",
    (Join-Path $PSScriptRoot '..\WURepair.ps1'),
    (Join-Path $PSScriptRoot 'WURepair.ps1')
)

$WURepairScriptPath = $null
foreach ($candidate in $candidatePaths) {
    if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
        $WURepairScriptPath = (Resolve-Path -LiteralPath $candidate).ProviderPath
        break
    }
}

if (-not $WURepairScriptPath) {
    Write-Output "WURepair.ps1 not found in any candidate path"
    exit 1
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportDir = Join-Path $env:ProgramData 'WURepair\Reports'
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$jsonReportPath = Join-Path $reportDir "WURepair-intune-$timestamp.json"
$journalPath = Join-Path $reportDir "WURepair-journal-$timestamp.json"

try {
    $powerShellExe = (Get-Command -Name powershell.exe -ErrorAction Stop).Source
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $WURepairScriptPath,
        '-Unattended',
        '-PlainText',
        '-JsonReport', $jsonReportPath,
        '-JournalPath', $journalPath,
        '-OverrideReadinessBlock'
    )

    $process = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    $repairExitCode = $process.ExitCode

    $statusMessage = switch ($repairExitCode) {
        0  { "Repair succeeded" }
        10 { "Repair completed with warnings" }
        20 { "One or more repair phases reported errors" }
        30 { "Post-repair connectivity still failed" }
        40 { "Administrator rights missing" }
        50 { "Repair cancelled" }
        default { "Repair exited with code $repairExitCode" }
    }

    if (Test-Path -LiteralPath $jsonReportPath) {
        $statusMessage += " | Report: $jsonReportPath"
    }

    Write-Output $statusMessage

    if ($repairExitCode -le 10) {
        exit 0
    }
    exit 1
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
