param(
    [string]$OutputPath,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [switch]$RequireSignature,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'

$windowsSecurityModule = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'
if (Test-Path -LiteralPath $windowsSecurityModule -PathType Leaf) {
    Import-Module -Name $windowsSecurityModule -Force -ErrorAction Stop
}
else {
    Import-Module -Name Microsoft.PowerShell.Security -Force -ErrorAction Stop
}

$windowsArchiveModule = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Archive\Microsoft.PowerShell.Archive.psd1'
if (Test-Path -LiteralPath $windowsArchiveModule -PathType Leaf) {
    Import-Module -Name $windowsArchiveModule -Force -ErrorAction Stop
}
else {
    Import-Module -Name Microsoft.PowerShell.Archive -Force -ErrorAction Stop
}
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
        [string]$SourceRoot,
        [string]$DestinationRoot
    )

    $resolvedSource = (Resolve-Path -LiteralPath $Source).ProviderPath
    $resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).ProviderPath.TrimEnd('\')
    $sourcePrefix = "$resolvedSourceRoot\"
    if (-not $resolvedSource.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package source is outside the repository root: $resolvedSource"
    }
    $relativePath = $resolvedSource.Substring($sourcePrefix.Length)
    $destination = Join-Path $DestinationRoot $relativePath
    $destinationParent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationParent)) {
        New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
    }
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

function ConvertTo-PortableArtifactReceipt {
    param([object[]]$Artifacts)

    return @($Artifacts | ForEach-Object {
        $artifact = $_
        [ordered]@{
            Name         = $artifact.Name
            Path         = Split-Path -Leaf ([string]$artifact.Path)
            SHA256       = $artifact.SHA256
            Signing      = [ordered]@{
                Status = $artifact.Signing.Status
                Files  = @($artifact.Signing.Files | ForEach-Object { Split-Path -Leaf ([string]$_) })
            }
            FileCatalog  = [ordered]@{
                Status = $artifact.FileCatalog.Status
                Path   = Split-Path -Leaf ([string]$artifact.FileCatalog.Path)
            }
            ChecksumFile = Split-Path -Leaf ([string]$artifact.ChecksumFile)
        }
    })
}

function ConvertTo-PortableVerificationReceipt {
    param([object]$Verification)

    $packages = @($Verification.Packages | ForEach-Object {
        $package = $_
        $moduleImport = $null
        if ($package.ModuleImport) {
            $moduleImport = [ordered]@{
                Name              = $package.ModuleImport.Name
                Version           = $package.ModuleImport.Version
                ExportedFunctions = @($package.ModuleImport.ExportedFunction)
            }
        }
        [ordered]@{
            Name                 = $package.Name
            FileName             = Split-Path -Leaf ([string]$package.ZipPath)
            SHA256               = $package.ZipSHA256
            ChecksumVerified     = $package.ChecksumVerified
            Catalog              = if ($package.Catalog) {
                [ordered]@{
                    Status   = $package.Catalog.Status
                    FileName = Split-Path -Leaf ([string]$package.Catalog.Path)
                }
            } else { $null }
            AuthenticodeStatuses = @($package.AuthenticodeStatuses)
            ModuleImport         = $moduleImport
        }
    })

    return [ordered]@{
        Tool       = $Verification.Tool
        Version    = $Verification.Version
        VerifiedAt = $Verification.VerifiedAt
        Packages   = $packages
    }
}

function Write-PortableReleaseReceipt {
    param(
        [hashtable]$Receipt,
        [string]$Path,
        [int]$Depth = 10
    )

    $json = $Receipt | ConvertTo-Json -Depth $Depth
    if ($json -match '[A-Za-z]:\\\\') {
        throw 'Release receipt contains an absolute Windows path.'
    }
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -Force
}

function New-WURepairArtifact {
    param(
        [string]$Name,
        [string[]]$Files,
        [string]$SourceRoot,
        [string]$StageRoot,
        [string]$OutputRoot,
        [AllowNull()][object]$Certificate
    )

    $artifactRoot = Join-Path $StageRoot $Name
    New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null
    foreach ($file in $Files) {
        Copy-PackageFile -Source $file -SourceRoot $SourceRoot -DestinationRoot $artifactRoot | Out-Null
    }

    $signing = Sign-PackageScripts -Root $artifactRoot -Certificate $Certificate -TimestampServer $TimestampServer -RequireSignature:$RequireSignature
    $checksums = Write-PackageChecksums -Root $artifactRoot
    $catalog = New-PackageFileCatalog -Root $artifactRoot

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
    Where-Object { $_.Name -like 'WURepair-*.zip' -or $_.Name -like 'WURepair-release-*.json' -or $_.Name -like 'WURepair-v*-SHA256SUMS.txt' } |
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
    $assetFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'assets') -Recurse -File | Select-Object -ExpandProperty FullName)
    $commonFiles += $assetFiles
    $moduleFiles = $commonFiles + @(
        (Join-Path $repoRoot 'WURepair.psm1'),
        (Join-Path $repoRoot 'WURepair.psd1')
    )

    $artifacts = @(
        New-WURepairArtifact -Name 'WURepair-script' -Files $commonFiles -SourceRoot $repoRoot -StageRoot $stageRoot -OutputRoot $outputRoot -Certificate $certificate
        New-WURepairArtifact -Name 'WURepair-module' -Files $moduleFiles -SourceRoot $repoRoot -StageRoot $stageRoot -OutputRoot $outputRoot -Certificate $certificate
    )
    $releaseChecksumPath = Join-Path $outputRoot ("WURepair-v{0}-SHA256SUMS.txt" -f $version)
    $releaseChecksumRows = @($artifacts | ForEach-Object {
        '{0}  {1}' -f $_.SHA256, (Split-Path -Leaf $_.Path)
    })
    Set-Content -LiteralPath $releaseChecksumPath -Value $releaseChecksumRows -Encoding ASCII -Force

    $receipt = [ordered]@{
        SchemaVersion         = 2
        Tool                  = 'WURepair'
        Version               = $version
        CreatedAt             = (Get-Date).ToString('o')
        SigningRequested      = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)
        RequireSignature      = [bool]$RequireSignature
        CertificateThumbprint = if ($certificate) { $certificate.Thumbprint } else { $null }
        ReleaseChecksumPath   = Split-Path -Leaf $releaseChecksumPath
        Artifacts             = @(ConvertTo-PortableArtifactReceipt -Artifacts $artifacts)
    }
    $receiptPath = Join-Path $outputRoot ("WURepair-release-v{0}.json" -f $version)
    Write-PortableReleaseReceipt -Receipt $receipt -Path $receiptPath -Depth 8

    $verification = & (Join-Path $PSScriptRoot 'Test-WURepairPackage.ps1') -PackageRoot $outputRoot -Version $version -RequireValidSignature:$RequireSignature
    $receipt['PackageVerification'] = ConvertTo-PortableVerificationReceipt -Verification $verification
    Write-PortableReleaseReceipt -Receipt $receipt -Path $receiptPath -Depth 10

    $receipt
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
