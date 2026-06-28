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
    $analysis = @(Invoke-ScriptAnalyzer -Path $scriptPath -Severity Error)
    $errors = @($analysis)
    if ($errors.Count -gt 0) {
        $errors | Format-Table -AutoSize RuleName, Severity, Line, Message
        exit 1
    }
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$testPath = Join-Path $repoRoot 'tests'
$testBatches = @(
    @(
        '*parses without*',
        '*uses timeout*',
        '*derives phase*',
        '*wires unattended*',
        '*wires mutation*',
        '*appends mutation*',
        '*applies file-content*'
    ),
    @(
        '*normalizes HRESULT*',
        '*reads registry*',
        '*removes only blocking*',
        '*waits for service*',
        '*wraps sc.exe*',
        '*parses Catalog*',
        '*validates Catalog*',
        '*rejects Catalog*',
        '*classifies WSUS*',
        '*preserves managed*',
        '*removes managed*',
        '*parses DISM*'
    )
)

foreach ($batch in $testBatches) {
    $result = Invoke-Pester -Path $testPath -Output Detailed -PassThru -FullNameFilter $batch
    if ($result.FailedCount -gt 0) {
        exit 1
    }
}

exit 0
