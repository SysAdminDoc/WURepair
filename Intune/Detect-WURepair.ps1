<#
.SYNOPSIS
    Intune Proactive Remediation - Detection Script for Windows Update health.
.DESCRIPTION
    Checks Windows Update service states, hosts file blocks, pending reboot,
    DISM component store health, and connectivity to Microsoft update endpoints.

    Exit 0 = Compliant (healthy).
    Exit 1 = Non-compliant (remediation needed).

    Designed for 64-bit PowerShell 5.1 hosting in Intune proactive remediations.
.NOTES
    Part of WURepair. Upload this as the detection script in Intune.
    Pair with Remediate-WURepair.ps1 as the remediation script.
#>

$ErrorActionPreference = 'SilentlyContinue'
$issues = New-Object 'System.Collections.Generic.List[string]'

$requiredServices = @(
    @{ Name = 'wuauserv'; DisplayName = 'Windows Update' },
    @{ Name = 'bits'; DisplayName = 'BITS' },
    @{ Name = 'cryptsvc'; DisplayName = 'Cryptographic Services' }
)

foreach ($svc in $requiredServices) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if (-not $service) {
        [void]$issues.Add("$($svc.DisplayName) service not found")
        continue
    }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
    $startVal = (Get-ItemProperty -LiteralPath $regPath -Name 'Start' -ErrorAction SilentlyContinue).Start
    if ($startVal -eq 4) {
        [void]$issues.Add("$($svc.DisplayName) is disabled")
    }
}

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
if (Test-Path -LiteralPath $hostsPath) {
    $knownDomains = @(
        'update.microsoft.com',
        'download.windowsupdate.com',
        'windowsupdate.com',
        'download.delivery.mp.microsoft.com',
        'ctldl.windowsupdate.com',
        'dl.delivery.mp.microsoft.com'
    )
    $hostsContent = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
    $blockedCount = 0
    foreach ($line in $hostsContent) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        foreach ($domain in $knownDomains) {
            if ($line -match "\b$([regex]::Escape($domain))\b") {
                if ($line -match '^(127\.0\.0\.1|0\.0\.0\.0|::1)\s') {
                    $blockedCount++
                    break
                }
            }
        }
    }
    if ($blockedCount -gt 0) {
        [void]$issues.Add("$blockedCount Microsoft update domain(s) blocked in hosts file")
    }
}

$rebootPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
foreach ($path in $rebootPaths) {
    if (Test-Path -LiteralPath $path) {
        [void]$issues.Add("Pending reboot detected")
        break
    }
}

$blockingPolicies = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DisableWindowsUpdateAccess' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'SetDisableUXWUAccess' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate' }
)
foreach ($policy in $blockingPolicies) {
    if (Test-Path -LiteralPath $policy.Path) {
        $val = (Get-ItemProperty -LiteralPath $policy.Path -Name $policy.Name -ErrorAction SilentlyContinue).$($policy.Name)
        if ($null -ne $val -and [int]$val -eq 1) {
            [void]$issues.Add("Blocking policy $($policy.Name) is set")
        }
    }
}

try {
    $dismResult = DISM /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
    if ($dismResult -match 'repairable') {
        [void]$issues.Add("DISM component store is repairable")
    }
    elseif ($dismResult -notmatch 'No component store corruption detected') {
        [void]$issues.Add("DISM component store status unknown")
    }
}
catch {
    [void]$issues.Add("DISM check failed: $($_.Exception.Message)")
}

$testEndpoints = @(
    'https://update.microsoft.com',
    'https://download.windowsupdate.com'
)
$connectivityFailed = 0
foreach ($endpoint in $testEndpoints) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $null = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        $connectivityFailed++
    }
}
if ($connectivityFailed -eq $testEndpoints.Count) {
    [void]$issues.Add("All Windows Update endpoints unreachable")
}

if ($issues.Count -gt 0) {
    $summary = "Non-compliant: $($issues.Count) issue(s) - $($issues[0])"
    if ($issues.Count -gt 1) {
        $summary += " (+$($issues.Count - 1) more)"
    }
    Write-Output $summary
    exit 1
}

Write-Output "Compliant: Windows Update components are healthy"
exit 0
