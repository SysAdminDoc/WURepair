param(
    [string]$OutputPath,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$RequireSignature,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'dist'
}

$manifestPath = Join-Path $repoRoot 'WURepair.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$version = [string]$manifest.Version

function Resolve-OutputPath {
    param([string]$Path)

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $resolved)) {
        New-Item -Path $resolved -ItemType Directory -Force | Out-Null
    }

    return (Resolve-Path -LiteralPath $resolved).ProviderPath
}

function Get-CodeSigningCertificate {
    param([string]$Thumbprint)

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        return $null
    }

    $normalized = ($Thumbprint -replace '\s', '').ToUpperInvariant()
    $certificates = @(Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
    return $certificates | Where-Object { ($_.Thumbprint -replace '\s', '').ToUpperInvariant() -eq $normalized } | Select-Object -First 1
}

function Copy-PackageFile {
    param(
        [string]$Source,
        [string]$DestinationRoot
    )

    $destination = Join-Path $DestinationRoot (Split-Path -Leaf $Source)
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    return $destination
}

function Sign-PackageScripts {
    param(
        [string]$Root,
        [AllowNull()][object]$Certificate,
        [string]$TimestampServer,
        [switch]$RequireSignature
    )

    $signableFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') })
    if ($null -eq $Certificate) {
        if ($RequireSignature) {
            throw 'A code-signing certificate is required but was not found.'
        }

        return [PSCustomObject]@{
            Status = 'Skipped'
            Files  = @($signableFiles | ForEach-Object { $_.FullName })
        }
    }

    $signed = @()
    foreach ($file in $signableFiles) {
        $signature = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $Certificate -TimestampServer $TimestampServer -ErrorAction Stop
        if ($signature.Status -ne 'Valid') {
            throw "Signing failed for $($file.FullName): $($signature.StatusMessage)"
        }
        $signed += $file.FullName
    }

    return [PSCustomObject]@{
        Status = 'Signed'
        Files  = $signed
    }
}

function New-PackageFileCatalog {
    param([string]$Root)

    $catalogPath = Join-Path $Root 'WURepair.cat'
    $catalogCommand = Get-Command -Name New-FileCatalog -ErrorAction SilentlyContinue
    if (-not $catalogCommand) {
        return [PSCustomObject]@{
            Status = 'Skipped'
            Path   = $catalogPath
        }
    }

    New-FileCatalog -Path $Root -CatalogFilePath $catalogPath -CatalogVersion 2.0 | Out-Null
    return [PSCustomObject]@{
        Status = 'Created'
        Path   = $catalogPath
    }
}

function Write-PackageChecksums {
    param([string]$Root)

    $checksumPath = Join-Path $Root 'SHA256SUMS.txt'
    $rows = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -ne $checksumPath } | Sort-Object FullName | ForEach-Object {
        $hash = Get-PackageFileSha256 -Path $_.FullName
        $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
        '{0}  {1}' -f $hash, $relative
    })
    Set-Content -LiteralPath $checksumPath -Value $rows -Encoding ASCII -Force
    return $checksumPath
}

function Get-PackageFileSha256 {
    param([string]$Path)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $bytes = $sha256.ComputeHash($stream)
        return (($bytes | ForEach-Object { $_.ToString('X2') }) -join '')
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function New-WURepairArtifact {
    param(
        [string]$Name,
        [string[]]$Files,
        [string]$StageRoot,
        [string]$OutputRoot,
        [AllowNull()][object]$Certificate
    )

    $artifactRoot = Join-Path $StageRoot $Name
    New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null
    foreach ($file in $Files) {
        Copy-PackageFile -Source $file -DestinationRoot $artifactRoot | Out-Null
    }

    $signing = Sign-PackageScripts -Root $artifactRoot -Certificate $Certificate -TimestampServer $TimestampServer -RequireSignature:$RequireSignature
    $catalog = New-PackageFileCatalog -Root $artifactRoot
    $checksums = Write-PackageChecksums -Root $artifactRoot

    $zipPath = Join-Path $OutputRoot ("{0}-v{1}.zip" -f $Name, $version)
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path $artifactRoot -DestinationPath $zipPath -Force

    return [PSCustomObject]@{
        Name          = $Name
        Path          = $zipPath
        SHA256        = Get-PackageFileSha256 -Path $zipPath
        Signing       = $signing
        FileCatalog   = $catalog
        ChecksumFile  = $checksums
    }
}

if (-not $SkipChecks) {
    & (Join-Path $repoRoot 'Invoke-LocalChecks.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "Invoke-LocalChecks.ps1 failed with exit code $LASTEXITCODE."
    }
}

$outputRoot = Resolve-OutputPath -Path $OutputPath
Get-ChildItem -LiteralPath $outputRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'WURepair-*.zip' -or $_.Name -like 'WURepair-release-*.json' } |
    Remove-Item -Force

$stageRoot = Join-Path $outputRoot ("stage_{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -Path $stageRoot -ItemType Directory -Force | Out-Null

try {
    $certificate = Get-CodeSigningCertificate -Thumbprint $CertificateThumbprint
    if ($RequireSignature -and $null -eq $certificate) {
        throw 'RequireSignature was specified, but no matching code-signing certificate was found.'
    }

    $commonFiles = @(
        (Join-Path $repoRoot 'WURepair.ps1'),
        (Join-Path $repoRoot 'README.md'),
        (Join-Path $repoRoot 'LICENSE'),
        (Join-Path $repoRoot 'CHANGELOG.md')
    )
    $moduleFiles = $commonFiles + @(
        (Join-Path $repoRoot 'WURepair.psm1'),
        (Join-Path $repoRoot 'WURepair.psd1')
    )

    $artifacts = @(
        New-WURepairArtifact -Name 'WURepair-script' -Files $commonFiles -StageRoot $stageRoot -OutputRoot $outputRoot -Certificate $certificate
        New-WURepairArtifact -Name 'WURepair-module' -Files $moduleFiles -StageRoot $stageRoot -OutputRoot $outputRoot -Certificate $certificate
    )

    $receipt = [ordered]@{
        Tool                  = 'WURepair'
        Version               = $version
        CreatedAt             = (Get-Date).ToString('o')
        SigningRequested      = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)
        RequireSignature      = [bool]$RequireSignature
        CertificateThumbprint = if ($certificate) { $certificate.Thumbprint } else { $null }
        Artifacts             = $artifacts
    }
    $receiptPath = Join-Path $outputRoot ("WURepair-release-v{0}.json" -f $version)
    Set-Content -LiteralPath $receiptPath -Value ($receipt | ConvertTo-Json -Depth 8) -Encoding UTF8 -Force

    $receipt
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
