param(
    [switch]$SkipAnalyzer,
    [string]$CoverageOutputPath
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

$artifactPatterns = @(
    @{ Path = $repoRoot; Filter = '*.psd1'; Kind = 'Data' },
    @{ Path = $repoRoot; Filter = '*.psm1'; Kind = 'Script' },
    @{ Path = $repoRoot; Filter = '*.ps1xml'; Kind = 'Xml' },
    @{ Path = (Join-Path $repoRoot 'Intune'); Filter = '*.ps1'; Kind = 'Script' },
    @{ Path = (Join-Path $repoRoot 'Remediation'); Filter = '*.ps1'; Kind = 'Script' },
    @{ Path = (Join-Path $repoRoot 'Package'); Filter = '*.ps1'; Kind = 'Script' },
    @{ Path = (Join-Path $repoRoot 'tools'); Filter = '*.ps1'; Kind = 'Script' }
)

foreach ($pattern in $artifactPatterns) {
    if (-not (Test-Path -LiteralPath $pattern.Path)) {
        continue
    }

    $artifacts = @(Get-ChildItem -LiteralPath $pattern.Path -Filter $pattern.Filter -File -ErrorAction Stop)
    foreach ($artifact in $artifacts) {
        switch ($pattern.Kind) {
            'Data' {
                $artifactTokens = $null
                $artifactParseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($artifact.FullName, [ref]$artifactTokens, [ref]$artifactParseErrors) | Out-Null
                if ($artifactParseErrors.Count -gt 0) {
                    $artifactParseErrors | ForEach-Object { Write-Error "$($artifact.FullName): $($_.Message)" }
                    exit 1
                }
                if ($artifact.Extension -ieq '.psd1') {
                    Test-ModuleManifest -Path $artifact.FullName -ErrorAction Stop | Out-Null
                }
            }
            'Xml' {
                [xml](Get-Content -LiteralPath $artifact.FullName -Raw -ErrorAction Stop) | Out-Null
            }
            default {
                $artifactTokens = $null
                $artifactParseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($artifact.FullName, [ref]$artifactTokens, [ref]$artifactParseErrors) | Out-Null
                if ($artifactParseErrors.Count -gt 0) {
                    $artifactParseErrors | ForEach-Object { Write-Error "$($artifact.FullName): $($_.Message)" }
                    exit 1
                }
            }
        }
    }
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$testPath = Join-Path $repoRoot 'tests'
$pesterArgs = @{
    Path     = $testPath
    Output   = 'Detailed'
    PassThru = $true
}

if ($CoverageOutputPath) {
    $coverageDirectory = Split-Path -Parent $CoverageOutputPath
    if ($coverageDirectory -and -not (Test-Path -LiteralPath $coverageDirectory)) {
        New-Item -Path $coverageDirectory -ItemType Directory -Force | Out-Null
    }

    $pesterConfiguration = New-PesterConfiguration
    $pesterConfiguration.Run.Path = @($testPath)
    $pesterConfiguration.Run.PassThru = $true
    $pesterConfiguration.Output.Verbosity = 'None'
    $pesterConfiguration.CodeCoverage.Enabled = $true
    $pesterConfiguration.CodeCoverage.Path = @($scriptPath)
    $pesterConfiguration.CodeCoverage.OutputPath = $CoverageOutputPath
    $pesterConfiguration.CodeCoverage.CoveragePercentTarget = 0
    $result = Invoke-Pester -Configuration $pesterConfiguration
}
else {
    $result = Invoke-Pester @pesterArgs
}
if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
