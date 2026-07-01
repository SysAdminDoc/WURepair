param(
    [string]$PackageRoot,
    [string]$Version,
    [switch]$RequireValidSignature
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $repoRoot 'dist'
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $manifest = Test-ModuleManifest -Path (Join-Path $repoRoot 'WURepair.psd1') -ErrorAction Stop
    $Version = [string]$manifest.Version
}

function Get-PackageVerifierSha256 {
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

function Resolve-PackageArtifactPath {
    param(
        [string]$PackageRoot,
        [AllowNull()][string]$ReceiptPath,
        [string]$FileName
    )

    if (-not [string]::IsNullOrWhiteSpace($ReceiptPath) -and (Test-Path -LiteralPath $ReceiptPath)) {
        return (Resolve-Path -LiteralPath $ReceiptPath).ProviderPath
    }

    $fallback = Join-Path $PackageRoot $FileName
    if (Test-Path -LiteralPath $fallback) {
        return (Resolve-Path -LiteralPath $fallback).ProviderPath
    }

    throw "Package artifact not found: $FileName"
}

function Test-PackageChecksums {
    param([string]$ExtractRoot)

    $checksumFile = Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File -Filter 'SHA256SUMS.txt' | Select-Object -First 1
    if (-not $checksumFile) {
        throw "SHA256SUMS.txt was not found in $ExtractRoot."
    }

    $verified = @()
    $rows = @(Get-Content -LiteralPath $checksumFile.FullName -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($row in $rows) {
        if ($row -notmatch '^(?<Hash>[A-Fa-f0-9]{64})\s+(?<Path>.+)$') {
            throw "Invalid checksum row in $($checksumFile.FullName): $row"
        }

        $relativePath = $Matches.Path.Trim()
        $target = Join-Path $checksumFile.Directory.FullName $relativePath
        if (-not (Test-Path -LiteralPath $target)) {
            throw "Checksum target missing: $relativePath"
        }

        $actual = Get-PackageVerifierSha256 -Path $target
        if ($actual -ne $Matches.Hash.ToUpperInvariant()) {
            throw "Checksum mismatch for $relativePath. Expected $($Matches.Hash); got $actual."
        }

        $verified += [PSCustomObject]@{
            RelativePath = $relativePath
            SHA256       = $actual
        }
    }

    return [PSCustomObject]@{
        Path          = $checksumFile.FullName
        VerifiedCount = $verified.Count
        Files         = $verified
    }
}

function Test-PackageCatalog {
    param([string]$ExtractRoot)

    $catalogFile = Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File -Filter 'WURepair.cat' | Select-Object -First 1
    if (-not $catalogFile) {
        return [PSCustomObject]@{
            Status = 'NotPresent'
            Path   = $null
        }
    }

    $catalogCommand = Get-Command -Name Test-FileCatalog -ErrorAction SilentlyContinue
    if (-not $catalogCommand) {
        return [PSCustomObject]@{
            Status = 'CommandUnavailable'
            Path   = $catalogFile.FullName
        }
    }

    $catalogResult = Test-FileCatalog -Path $catalogFile.Directory.FullName -CatalogFilePath $catalogFile.FullName -Detailed -ErrorAction Stop
    $status = [string]$catalogResult.Status
    if ($status -ne 'Valid') {
        throw "File catalog validation failed for $($catalogFile.FullName): $status"
    }

    return [PSCustomObject]@{
        Status = $status
        Path   = $catalogFile.FullName
    }
}

function Get-PackageAuthenticodeSummary {
    param(
        [string]$ExtractRoot,
        [switch]$RequireValidSignature
    )

    $files = @(Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') })
    $results = @($files | ForEach-Object {
        $signature = Get-AuthenticodeSignature -FilePath $_.FullName -ErrorAction Stop
        [PSCustomObject]@{
            Path          = $_.FullName
            RelativePath  = $_.FullName.Substring($ExtractRoot.Length).TrimStart('\')
            Status        = [string]$signature.Status
            StatusMessage = [string]$signature.StatusMessage
        }
    })

    if ($RequireValidSignature) {
        $invalid = @($results | Where-Object { $_.Status -ne 'Valid' })
        if ($invalid.Count -gt 0) {
            throw "Authenticode validation failed for $($invalid.Count) PowerShell artifact(s)."
        }
    }

    return $results
}

function Import-ExtractedWURepairModule {
    param([string]$ExtractRoot)

    $manifestPath = Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File -Filter 'WURepair.psd1' | Select-Object -First 1
    if (-not $manifestPath) {
        throw "WURepair.psd1 was not found in $ExtractRoot."
    }

    $module = Import-Module -Name $manifestPath.FullName -Force -PassThru -ErrorAction Stop
    try {
        return [PSCustomObject]@{
            Name             = $module.Name
            Version          = [string]$module.Version
            Path             = $manifestPath.FullName
            ExportedFunction = @($module.ExportedFunctions.Keys | Sort-Object)
        }
    }
    finally {
        Remove-Module -Name $module.Name -Force -ErrorAction SilentlyContinue
    }
}

$packageRootPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PackageRoot)
if (-not (Test-Path -LiteralPath $packageRootPath)) {
    throw "Package root not found: $packageRootPath"
}

$receiptPath = Join-Path $packageRootPath ("WURepair-release-v{0}.json" -f $Version)
if (-not (Test-Path -LiteralPath $receiptPath)) {
    throw "Release receipt not found: $receiptPath"
}

$receipt = Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop | ConvertFrom-Json
if ([string]$receipt.Version -ne [string]$Version) {
    throw "Release receipt version mismatch. Expected $Version; got $($receipt.Version)."
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("WURepairPackageVerify_{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $packageResults = @()
    foreach ($packageName in @('WURepair-script', 'WURepair-module')) {
        $zipName = "{0}-v{1}.zip" -f $packageName, $Version
        $artifactReceipt = @($receipt.Artifacts | Where-Object { $_.Name -eq $packageName }) | Select-Object -First 1
        if (-not $artifactReceipt) {
            throw "Release receipt does not include $packageName."
        }

        $zipPath = Resolve-PackageArtifactPath -PackageRoot $packageRootPath -ReceiptPath ([string]$artifactReceipt.Path) -FileName $zipName
        $zipHash = Get-PackageVerifierSha256 -Path $zipPath
        if ($zipHash -ne [string]$artifactReceipt.SHA256) {
            throw "Release receipt SHA256 mismatch for $zipName. Expected $($artifactReceipt.SHA256); got $zipHash."
        }

        $extractRoot = Join-Path $tempRoot $packageName
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
        $checksumResult = Test-PackageChecksums -ExtractRoot $extractRoot
        $catalogResult = Test-PackageCatalog -ExtractRoot $extractRoot
        $signatureResults = Get-PackageAuthenticodeSummary -ExtractRoot $extractRoot -RequireValidSignature:$RequireValidSignature

        $moduleImport = $null
        if ($packageName -eq 'WURepair-module') {
            $moduleImport = Import-ExtractedWURepairModule -ExtractRoot $extractRoot
            if ([string]$moduleImport.Version -ne [string]$Version) {
                throw "Extracted module version mismatch. Expected $Version; got $($moduleImport.Version)."
            }
        }

        $packageResults += [PSCustomObject]@{
            Name                 = $packageName
            ZipPath              = $zipPath
            ZipSHA256            = $zipHash
            ChecksumFile         = $checksumResult.Path
            ChecksumVerified     = $checksumResult.VerifiedCount
            Catalog              = $catalogResult
            AuthenticodeStatuses = @($signatureResults | Group-Object Status | ForEach-Object {
                [PSCustomObject]@{
                    Status = $_.Name
                    Count  = $_.Count
                }
            })
            ModuleImport         = $moduleImport
        }
    }

    [PSCustomObject]@{
        Tool         = 'WURepair'
        Version      = $Version
        PackageRoot  = $packageRootPath
        ReceiptPath  = $receiptPath
        VerifiedAt   = (Get-Date).ToString('o')
        Packages     = $packageResults
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
