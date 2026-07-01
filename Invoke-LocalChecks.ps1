param(
    [switch]$SkipAnalyzer,
    [string]$CoverageOutputPath,
    [string]$PackageRoot,
    [switch]$SkipPackageVerification,
    [switch]$ListToolVersions
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $repoRoot 'WURepair.ps1'

$Script:MinPesterVersion = [version]'5.4.0'
$Script:MinAnalyzerVersion = [version]'1.22.0'

function Get-WURepairToolVersions {
    $pesterModule = Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    $analyzerModule = Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1

    return [PSCustomObject]@{
        Pester              = if ($pesterModule) { [version]$pesterModule.Version } else { $null }
        PesterPath          = if ($pesterModule) { $pesterModule.ModuleBase } else { $null }
        PSScriptAnalyzer    = if ($analyzerModule) { [version]$analyzerModule.Version } else { $null }
        PSScriptAnalyzerPath = if ($analyzerModule) { $analyzerModule.ModuleBase } else { $null }
        PowerShell          = [version]$PSVersionTable.PSVersion
    }
}

$toolVersions = Get-WURepairToolVersions
Write-Host "Validation tool versions:"
Write-Host "  PowerShell:       $($toolVersions.PowerShell)"
Write-Host "  Pester:           $(if ($toolVersions.Pester) { $toolVersions.Pester } else { 'NOT INSTALLED' })"
Write-Host "  PSScriptAnalyzer: $(if ($toolVersions.PSScriptAnalyzer) { $toolVersions.PSScriptAnalyzer } else { 'NOT INSTALLED' })"
Write-Host "  Minimum Pester:           $Script:MinPesterVersion"
Write-Host "  Minimum PSScriptAnalyzer: $Script:MinAnalyzerVersion"
Write-Host ""

if ($ListToolVersions) {
    exit 0
}

if (-not $toolVersions.Pester) {
    Write-Error "Pester is not installed. Install with: Install-Module -Name Pester -MinimumVersion $Script:MinPesterVersion -Force -SkipPublisherCheck"
    exit 1
}
if ($toolVersions.Pester -lt $Script:MinPesterVersion) {
    Write-Error "Pester $($toolVersions.Pester) is below the tested minimum $Script:MinPesterVersion. Update with: Install-Module -Name Pester -MinimumVersion $Script:MinPesterVersion -Force -SkipPublisherCheck"
    exit 1
}

if (-not $SkipAnalyzer) {
    if (-not $toolVersions.PSScriptAnalyzer) {
        Write-Error "PSScriptAnalyzer is not installed. Install with: Install-Module -Name PSScriptAnalyzer -MinimumVersion $Script:MinAnalyzerVersion -Force"
        exit 1
    }
    if ($toolVersions.PSScriptAnalyzer -lt $Script:MinAnalyzerVersion) {
        Write-Error "PSScriptAnalyzer $($toolVersions.PSScriptAnalyzer) is below the tested minimum $Script:MinAnalyzerVersion. Update with: Install-Module -Name PSScriptAnalyzer -MinimumVersion $Script:MinAnalyzerVersion -Force"
        exit 1
    }
}

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

if (-not $SkipPackageVerification) {
    $verifierPath = Join-Path $repoRoot 'tools\Test-WURepairPackage.ps1'
    $manifest = Test-ModuleManifest -Path (Join-Path $repoRoot 'WURepair.psd1') -ErrorAction Stop
    $currentVersion = [string]$manifest.Version
    $packageRootToCheck = if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
        Join-Path $repoRoot 'dist'
    }
    else {
        $PackageRoot
    }

    $expectedArtifacts = @(
        (Join-Path $packageRootToCheck ("WURepair-script-v{0}.zip" -f $currentVersion)),
        (Join-Path $packageRootToCheck ("WURepair-module-v{0}.zip" -f $currentVersion)),
        (Join-Path $packageRootToCheck ("WURepair-release-v{0}.json" -f $currentVersion))
    )
    $missingArtifacts = @($expectedArtifacts | Where-Object { -not (Test-Path -LiteralPath $_) })

    if ($missingArtifacts.Count -eq 0) {
        & $verifierPath -PackageRoot $packageRootToCheck -Version $currentVersion | Out-Host
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
        Write-Error "Package verification requested, but current v$currentVersion artifacts are missing from $packageRootToCheck."
        exit 1
    }
    else {
        Write-Host "Package verification skipped: no complete v$currentVersion artifact set in $packageRootToCheck."
    }
}

exit 0
