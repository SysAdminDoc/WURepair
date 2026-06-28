param(
    [switch]$SkipAnalyzer
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot 'WURepair.ps1'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
    $analysis = @(Invoke-ScriptAnalyzer -Path $scriptPath)
    $errors = @($analysis | Where-Object { $_.Severity -eq 'Error' })
    if ($errors.Count -gt 0) {
        $errors | Format-Table -AutoSize RuleName, Severity, Line, Message
        exit 1
    }

    if ($analysis.Count -gt 0) {
        $analysis | Sort-Object Line, RuleName | Format-Table -AutoSize RuleName, Severity, Line, Message
    }
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $repoRoot 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
