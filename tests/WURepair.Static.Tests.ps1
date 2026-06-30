Describe 'WURepair static contract' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:ScriptPath = Join-Path $script:RepoRoot 'WURepair.ps1'
        $script:Content = Get-Content -LiteralPath $script:ScriptPath -Raw
        $script:Tokens = $null
        $script:ParseErrors = $null
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$script:Tokens, [ref]$script:ParseErrors)

        function Import-WURepairFunction {
            param([string[]]$Name)

            foreach ($functionName in $Name) {
                $functionAst = $script:Ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
                }, $true)

                if (-not $functionAst) {
                    throw "Function not found in WURepair.ps1: $functionName"
                }

                $definition = $functionAst.Extent.Text -replace '^function\s+([^\s{]+)', 'function global:$1'
                . ([scriptblock]::Create($definition))
            }
        }

        Import-WURepairFunction -Name @(
            'Write-Log',
            'Write-UiList',
            'Write-UiMetric',
            'Write-UiSubheading',
            'Show-Banner',
            'Initialize-WUMutationJournal',
            'Save-WUMutationJournal',
            'Get-WUMutationJournalSummary',
            'Add-WUMutationJournalEntry',
            'Get-WUPathSnapshot',
            'Get-WURegistryValueSnapshot',
            'Restore-WURegistryValueSnapshot',
            'Set-WURegistryValueWithJournal',
            'Remove-WURegistryValueWithJournal',
            'ConvertTo-WURegExePath',
            'Invoke-WUMutationRollback',
            'ConvertTo-WUErrorCode',
            'Get-WUErrorArticleLink',
            'Get-WULogSources',
            'ConvertTo-WULogTimelineEntry',
            'Get-WULogTimeline',
            'Get-WULogTimelineSummary',
            'Get-WURegistryValue',
            'Test-WUConfiguredPolicyValue',
            'Get-WUManagedUpdateSourceGuardrail',
            'Repair-HostsFile',
            'Repair-UpdatePolicies',
            'Wait-WUServiceState',
            'Invoke-WUServiceControl',
            'Get-WUConvertedTraceLogPath',
            'Convert-WUCatalogHtmlText',
            'Get-WUFileSha256',
            'Test-WUCatalogPackageValidation',
            'Resolve-WUSupportBundlePath',
            'ConvertTo-WUSupportBundleText',
            'Add-WUSupportBundleTextFile',
            'Add-WUSupportBundleFile',
            'Add-WUSupportBundleTailFile',
            'Add-WUSupportBundleEventExport',
            'New-WUSupportBundle',
            'Convert-WUSizeToMegabyte',
            'Get-ComponentStoreAnalysis',
            'Resolve-DismRepairSource',
            'Get-DismRestoreHealthPlan',
            'Invoke-ComponentStoreCleanup',
            'Invoke-DISM',
            'Resolve-WURepairPhaseSelection',
            'Get-CommandLineOptionValue'
        )
    }

    BeforeEach {
        $Script:Config = @{
            LogPath                            = Join-Path $TestDrive 'WURepair.log'
            TempPath                           = Join-Path $TestDrive 'Temp'
            Unattended                         = $true
            PlainText                          = $false
            ComponentStoreResetBaseThresholdMB = 1024
            Ui                                 = @{}
        }
        $Script:CurrentPhaseTelemetry = $null
        $Script:MicrosoftDomains = @('update.microsoft.com', 'download.windowsupdate.com')
        $Script:WUErrorReferenceUrl = 'https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference'
        $Script:WUErrorSearchUrl = 'https://www.bing.com/search?q='
        $Script:WUErrorArticleMap = @{
            '0x80240016' = 'https://learn.microsoft.com/test/80240016'
        }
        $Script:CatalogPackageValidationResults = @()
    }

    AfterAll {
        @(
            'Write-Log',
            'Write-UiList',
            'Write-UiMetric',
            'Write-UiSubheading',
            'Show-Banner',
            'Initialize-WUMutationJournal',
            'Save-WUMutationJournal',
            'Get-WUMutationJournalSummary',
            'Add-WUMutationJournalEntry',
            'Get-WUPathSnapshot',
            'Get-WURegistryValueSnapshot',
            'Restore-WURegistryValueSnapshot',
            'Set-WURegistryValueWithJournal',
            'Remove-WURegistryValueWithJournal',
            'ConvertTo-WURegExePath',
            'Invoke-WUMutationRollback',
            'ConvertTo-WUErrorCode',
            'Get-WUErrorArticleLink',
            'Get-WULogSources',
            'ConvertTo-WULogTimelineEntry',
            'Get-WULogTimeline',
            'Get-WULogTimelineSummary',
            'Get-WURegistryValue',
            'Test-WUConfiguredPolicyValue',
            'Get-WUManagedUpdateSourceGuardrail',
            'Repair-HostsFile',
            'Repair-UpdatePolicies',
            'Wait-WUServiceState',
            'Invoke-WUServiceControl',
            'Get-WUConvertedTraceLogPath',
            'Convert-WUCatalogHtmlText',
            'Get-WUFileSha256',
            'Test-WUCatalogPackageValidation',
            'Resolve-WUSupportBundlePath',
            'ConvertTo-WUSupportBundleText',
            'Add-WUSupportBundleTextFile',
            'Add-WUSupportBundleFile',
            'Add-WUSupportBundleTailFile',
            'Add-WUSupportBundleEventExport',
            'New-WUSupportBundle',
            'Convert-WUSizeToMegabyte',
            'Get-ComponentStoreAnalysis',
            'Resolve-DismRepairSource',
            'Get-DismRestoreHealthPlan',
            'Invoke-ComponentStoreCleanup',
            'Invoke-DISM',
            'Resolve-WURepairPhaseSelection',
            'Get-CommandLineOptionValue',
            'sc.exe',
            'DISM',
            'Get-FileHash',
            'Get-AuthenticodeSignature'
        ) | ForEach-Object {
            if (Test-Path -LiteralPath "Function:\$_") {
                Remove-Item -LiteralPath "Function:\$_" -Force
            }
        }
    }

    It 'parses without syntax errors' {
        $script:ParseErrors.Count | Should -Be 0
        $script:Ast | Should -Not -BeNullOrEmpty
    }

    It 'uses timeout-safe service control instead of blocking service cmdlets' {
        $script:Content | Should -Match 'function Invoke-WUServiceControl'
        $script:Content | Should -Match 'sc\.exe \$Action \$ServiceName'
        $script:Content | Should -Not -Match '\b(Start-Service|Stop-Service|Restart-Service)\b|Set-Service\s+-Status'
    }

    It 'derives phase status from warning and error telemetry' {
        $script:Content | Should -Match '\$Script:CurrentPhaseTelemetry'
        $script:Content | Should -Match 'Status\s*=\s*\$phaseStatus'
        $script:Content | Should -Not -Match "Status\s*=\s*'Completed'"
    }

    It 'wires unattended mode to no-host execution and automation exit codes' {
        $script:Content | Should -Match '\[switch\]\$Unattended'
        $script:Content | Should -Match '\$Script:Config\.Unattended'
        $script:Content | Should -Match '\$Script:ExitCodes'
        $script:Content | Should -Match 'ConnectivityFailure'
        $script:Content | Should -Match 'exit \$exitCode'
    }

    It 'emits plain text status lines without colors or progress chrome' {
        $Script:Config.Unattended = $false
        $Script:Config.PlainText = $true
        $Script:Config.Version = '9.9.9-test'
        $script:HostLines = @()
        Mock Write-Host {
            param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Object)
            $script:HostLines += (($Object | ForEach-Object { [string]$_ }) -join ' ')
        }
        Mock Clear-Host { throw 'Clear-Host should not run in plain text mode.' }

        Show-Banner
        Write-Log 'Plain output started'
        Write-Log 'Plain section' -Level SECTION
        Write-UiMetric -Label 'Mode' -Value 'PlainText'
        Write-UiList -Title 'Items' -Items @('First item')

        $output = $script:HostLines -join "`n"
        $output | Should -Match 'WURepair v9.9.9-test'
        $output | Should -Match '\[INFO\] Plain output started'
        $output | Should -Match '== Plain section =='
        $output | Should -Match 'Mode: PlainText'
        $output | Should -Match '- First item'
        $output | Should -Not -Match '\[OK\]|\[!\]'
        Should -Invoke Clear-Host -Times 0 -Exactly
    }

    It 'wires mutation journals and rollback entry points' {
        $script:Content | Should -Match 'function Initialize-WUMutationJournal'
        $script:Content | Should -Match 'function Invoke-WUMutationRollback'
        $script:Content | Should -Match '\[string\]\$RollbackJournal'
        $script:Content | Should -Match '\[switch\]\$ApplyRollback'
        $script:Content | Should -Match 'MutationJournalPath'
    }

    It 'appends mutation journal entries to disk' {
        $journalPath = Join-Path $TestDrive 'journal.json'
        Initialize-WUMutationJournal -Path $journalPath
        Add-WUMutationJournalEntry -Category 'Test' -Action 'ChangeValue' -Target 'target-1' -Before @{ Value = 'before' } -After @{ Value = 'after' } -RollbackType 'RestoreFileContent' -RollbackData @{ Path = 'target-1'; Content = @('before') } -Succeeded $true

        $saved = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        $saved.SchemaVersion | Should -Be 1
        @($saved.Entries).Count | Should -Be 1
        $saved.Entries[0].Category | Should -Be 'Test'
        $saved.Entries[0].Reversible | Should -BeTrue

        $summary = Get-WUMutationJournalSummary
        $summary.EntryCount | Should -Be 1
        $summary.ReversibleCount | Should -Be 1
    }

    It 'applies file-content rollback entries from a journal' {
        $journalPath = Join-Path $TestDrive 'rollback.json'
        $targetPath = Join-Path $TestDrive 'hosts'
        Set-Content -LiteralPath $targetPath -Value @('changed')

        Initialize-WUMutationJournal -Path $journalPath
        Add-WUMutationJournalEntry -Category 'Hosts' -Action 'RemoveMicrosoftBlocks' -Target $targetPath -Before @{ Content = @('original') } -After @{ Content = @('changed') } -RollbackType 'RestoreFileContent' -RollbackData @{ Path = $targetPath; Content = @('original') } -Succeeded $true

        Invoke-WUMutationRollback -Path $journalPath -Apply | Should -BeTrue
        (Get-Content -LiteralPath $targetPath -Raw).Trim() | Should -Be 'original'
    }

    It 'normalizes HRESULT tokens and maps known Windows Update errors' {
        ConvertTo-WUErrorCode -Token '-2145124328' | Should -Be '0x80240018'
        ConvertTo-WUErrorCode -Token '0x80240016' | Should -Be '0x80240016'
        ConvertTo-WUErrorCode -Token 'not-a-code' | Should -BeNullOrEmpty
        Get-WUErrorArticleLink -ErrorCode '0x80240016' | Should -Be 'https://learn.microsoft.com/test/80240016'
        Get-WUErrorArticleLink -ErrorCode '0x8024FFFF' | Should -Be $Script:WUErrorReferenceUrl
    }

    It 'reads registry values through a mockable registry boundary' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { [PSCustomObject]@{ UseWUServer = 1 } }

        Get-WURegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'UseWUServer' | Should -Be 1

        Should -Invoke Test-Path -Times 1 -Exactly
        Should -Invoke Get-ItemProperty -Times 1 -Exactly
    }

    It 'classifies WSUS and WUfB source policies as managed update sources' {
        $wsusGuardrail = Get-WUManagedUpdateSourceGuardrail -WUServer 'https://wsus.contoso.local' -WUStatusServer 'https://wsus.contoso.local' -UseWUServer 1
        $wsusGuardrail.IsManagedSource | Should -BeTrue
        $wsusGuardrail.Reason | Should -Match 'WSUS/SUP'

        $wufbGuardrail = Get-WUManagedUpdateSourceGuardrail -SetQualitySource 1 -SetFeatureSource 1
        $wufbGuardrail.IsManagedSource | Should -BeTrue
        $wufbGuardrail.Reason | Should -Match 'WUfB Quality'
    }

    It 'preserves managed update-source policies unless reset is explicit' {
        $values = @{
            WUServer                   = 'https://wsus.contoso.local'
            WUStatusServer             = 'https://wsus.contoso.local'
            UseWUServer                = 1
            DisableWindowsUpdateAccess = 1
            SetDisableUXWUAccess       = 1
        }
        Mock Get-WURegistryValue {
            if ($values.ContainsKey($Name)) {
                return $values[$Name]
            }
            return $null
        }
        Mock Remove-WURegistryValueWithJournal { $true }

        Repair-UpdatePolicies

        Should -Invoke Remove-WURegistryValueWithJournal -Times 0 -Exactly -ParameterFilter { $Name -eq 'WUServer' }
        Should -Invoke Remove-WURegistryValueWithJournal -Times 0 -Exactly -ParameterFilter { $Name -eq 'UseWUServer' }
        Should -Invoke Remove-WURegistryValueWithJournal -Times 1 -Exactly -ParameterFilter { $Name -eq 'DisableWindowsUpdateAccess' }
        Should -Invoke Remove-WURegistryValueWithJournal -Times 1 -Exactly -ParameterFilter { $Name -eq 'SetDisableUXWUAccess' }
    }

    It 'removes managed update-source policies when reset is explicit' {
        $values = @{
            WUServer       = 'https://wsus.contoso.local'
            WUStatusServer = 'https://wsus.contoso.local'
            UseWUServer    = 1
        }
        Mock Get-WURegistryValue {
            if ($values.ContainsKey($Name)) {
                return $values[$Name]
            }
            return $null
        }
        Mock Remove-WURegistryValueWithJournal { $true }

        Repair-UpdatePolicies -ResetManagedUpdatePolicy

        Should -Invoke Remove-WURegistryValueWithJournal -Times 1 -Exactly -ParameterFilter { $Name -eq 'WUServer' }
        Should -Invoke Remove-WURegistryValueWithJournal -Times 1 -Exactly -ParameterFilter { $Name -eq 'WUStatusServer' }
        Should -Invoke Remove-WURegistryValueWithJournal -Times 1 -Exactly -ParameterFilter { $Name -eq 'UseWUServer' }
    }

    It 'redacts support bundle identifiers by default' {
        $originalUserName = $env:USERNAME
        $originalUserProfile = $env:USERPROFILE
        $originalComputerName = $env:COMPUTERNAME
        try {
            $env:USERNAME = 'Alice'
            $env:USERPROFILE = 'C:\Users\Alice'
            $env:COMPUTERNAME = 'DESKTOP-TEST'
            $sample = 'Alice used C:\Users\Alice\Desktop on DESKTOP-TEST with S-1-5-21-111-222-333-1001.'

            $redacted = ConvertTo-WUSupportBundleText -Text $sample
            $redacted | Should -Not -Match 'Alice'
            $redacted | Should -Not -Match 'DESKTOP-TEST'
            $redacted | Should -Not -Match 'S-1-5-21'
            $redacted | Should -Match '<redacted-user>'
            $redacted | Should -Match '<redacted-computer>'

            $plain = ConvertTo-WUSupportBundleText -Text $sample -NoRedact
            $plain | Should -Match 'Alice'
            $plain | Should -Match 'DESKTOP-TEST'
        }
        finally {
            $env:USERNAME = $originalUserName
            $env:USERPROFILE = $originalUserProfile
            $env:COMPUTERNAME = $originalComputerName
        }
    }

    It 'creates a redacted support bundle zip with manifest and core artifacts' {
        $originalUserName = $env:USERNAME
        $originalUserProfile = $env:USERPROFILE
        $originalComputerName = $env:COMPUTERNAME
        try {
            $env:USERNAME = 'Alice'
            $env:USERPROFILE = 'C:\Users\Alice'
            $env:COMPUTERNAME = 'DESKTOP-TEST'
            $Script:Config.TempPath = Join-Path $TestDrive 'Temp'
            $Script:Config.LogPath = Join-Path $TestDrive 'WURepair.log'
            $Script:Config.Version = '9.9.9-test'
            Set-Content -LiteralPath $Script:Config.LogPath -Value 'Alice on DESKTOP-TEST at C:\Users\Alice\Desktop'
            $jsonPath = Join-Path $TestDrive 'report.json'
            Set-Content -LiteralPath $jsonPath -Value '{"ComputerName":"DESKTOP-TEST","User":"Alice"}'
            Mock Get-WUConvertedTraceLogPath { $null }
            Mock Get-WinEvent { @() }

            $bundlePath = Join-Path $TestDrive 'support.zip'
            $timeline = @(
                [PSCustomObject]@{
                    Timestamp  = '2026-06-29T12:00:00.0000000'
                    Component  = 'Agent'
                    Level      = 'Error'
                    Code       = '0x80240016'
                    Message    = 'Alice saw an update failure on DESKTOP-TEST'
                    SourceFile = '%WINDIR%\WindowsUpdate.log'
                    Line       = 42
                }
            )
            $result = New-WUSupportBundle -Path $bundlePath -JsonReportPath $jsonPath -ModeLabel 'Test' -OverallStatus 'Success' -ExitCode 0 -PhaseResults @() -WULogTimeline $timeline

            Test-Path -LiteralPath $result | Should -BeTrue
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($result)
            try {
                $entryNames = @($zip.Entries | Select-Object -ExpandProperty FullName)
                $entryNames | Should -Contain 'manifest.json'
                $entryNames | Should -Contain 'WURepair.log'
                $entryNames | Should -Contain 'WURepair-report.json'
                $entryNames | Should -Contain 'logs/WURepair-wulog.json'
                $entryNames | Should -Contain 'logs/CBS.tail.log'
                $entryNames | Should -Contain 'events/WURepair-Application.json'

                $logEntry = $zip.GetEntry('WURepair.log')
                $reader = New-Object System.IO.StreamReader($logEntry.Open())
                try {
                    $logContent = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }

                $logContent | Should -Not -Match 'Alice'
                $logContent | Should -Not -Match 'DESKTOP-TEST'
            }
            finally {
                $zip.Dispose()
            }
        }
        finally {
            $env:USERNAME = $originalUserName
            $env:USERPROFILE = $originalUserProfile
            $env:COMPUTERNAME = $originalComputerName
        }
    }

    It 'removes only blocking Microsoft entries from a temp hosts file' {
        $originalSystemRoot = $env:SystemRoot
        try {
            $env:SystemRoot = Join-Path $TestDrive 'Windows'
            $hostsDir = Join-Path $env:SystemRoot 'System32\drivers\etc'
            New-Item -Path $hostsDir -ItemType Directory -Force | Out-Null
            $hostsPath = Join-Path $hostsDir 'hosts'
            Set-Content -Path $hostsPath -Value @(
                '127.0.0.1 update.microsoft.com'
                '0.0.0.0 download.windowsupdate.com'
                '127.0.0.1 example.invalid'
                '20.54.1.1 update.microsoft.com'
            )

            Repair-HostsFile

            $updatedHosts = Get-Content -Path $hostsPath -Raw
            $updatedHosts | Should -Not -Match '127\.0\.0\.1 update\.microsoft\.com'
            $updatedHosts | Should -Not -Match '0\.0\.0\.0 download\.windowsupdate\.com'
            $updatedHosts | Should -Match '127\.0\.0\.1 example\.invalid'
            $updatedHosts | Should -Match '20\.54\.1\.1 update\.microsoft\.com'
            @(Get-ChildItem -Path $hostsDir -Filter 'hosts.backup.*').Count | Should -Be 1
        }
        finally {
            $env:SystemRoot = $originalSystemRoot
        }
    }

    It 'waits for service state with mocked service and sleep calls' {
        Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
        Mock Start-Sleep {}

        Wait-WUServiceState -ServiceName 'bits' -DesiredState 'Running' -TimeoutSeconds 1 | Should -BeTrue

        Should -Invoke Get-Service -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'wraps sc.exe service control and returns command telemetry' {
        Mock Wait-WUServiceState { $true }
        function global:sc.exe {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            cmd.exe /c exit 0 | Out-Null
            "mock sc $($Arguments -join ' ')"
        }

        $result = Invoke-WUServiceControl -ServiceName 'bits' -Action 'stop' -DesiredState 'Stopped' -TimeoutSeconds 7

        $result.ServiceName | Should -Be 'bits'
        $result.Action | Should -Be 'stop'
        $result.DesiredState | Should -Be 'Stopped'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be 'mock sc stop bits'
        $result.StateReached | Should -BeTrue
        Should -Invoke Wait-WUServiceState -Times 1 -Exactly -ParameterFilter {
            $ServiceName -eq 'bits' -and $DesiredState -eq 'Stopped' -and $TimeoutSeconds -eq 7
        }
    }

    It 'parses Catalog HTML text and localized size strings' {
        Convert-WUCatalogHtmlText -Html '<td>Servicing&nbsp;Stack<br>Update</td>' | Should -Be 'Servicing Stack Update'
        Convert-WUSizeToMegabyte -SizeText '1.5 GB' | Should -Be 1536
        Convert-WUSizeToMegabyte -SizeText '512 KB' | Should -Be 0.5
        Convert-WUSizeToMegabyte -SizeText '1,5 GB' | Should -Be 1536
    }

    It 'computes SHA256 without requiring Get-FileHash' {
        $hashTarget = Join-Path $TestDrive 'hash.txt'
        Set-Content -LiteralPath $hashTarget -Value 'abc' -NoNewline

        Get-WUFileSha256 -Path $hashTarget | Should -Be 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    }

    It 'validates Catalog packages with Microsoft signature and SHA256 hash' {
        Mock Test-Path { $true }
        Mock Get-Item { [PSCustomObject]@{ Length = 4096 } }
        function global:Get-FileHash {
            [PSCustomObject]@{ Hash = 'ABCDEF123456' }
        }
        function global:Get-AuthenticodeSignature {
            [PSCustomObject]@{
                Status            = 'Valid'
                StatusMessage     = 'Signature verified.'
                SignerCertificate = [PSCustomObject]@{
                    Subject = 'CN=Microsoft Windows'
                    Issuer  = 'CN=Microsoft Code Signing PCA'
                }
            }
        }

        $result = Test-WUCatalogPackageValidation -Path (Join-Path $TestDrive 'package.msu') -SourceUrl 'https://catalog.test/package.msu'

        $result.IsValid | Should -BeTrue
        $result.SHA256 | Should -Be 'ABCDEF123456'
        $result.IsMicrosoftSigned | Should -BeTrue
        @($Script:CatalogPackageValidationResults).Count | Should -Be 1
    }

    It 'rejects Catalog packages when Authenticode validation fails' {
        Mock Test-Path { $true }
        Mock Get-Item { [PSCustomObject]@{ Length = 4096 } }
        function global:Get-FileHash {
            [PSCustomObject]@{ Hash = 'ABCDEF123456' }
        }
        function global:Get-AuthenticodeSignature {
            [PSCustomObject]@{
                Status            = 'NotSigned'
                StatusMessage     = 'No signature was present.'
                SignerCertificate = $null
            }
        }

        $result = Test-WUCatalogPackageValidation -Path (Join-Path $TestDrive 'package.msu')

        $result.IsValid | Should -BeFalse
        $result.AuthenticodeStatus | Should -Be 'NotSigned'
        $result.IsMicrosoftSigned | Should -BeFalse
        @($Script:CatalogPackageValidationResults).Count | Should -Be 1
    }

    It 'parses DISM AnalyzeComponentStore output through a mocked DISM process' {
        function global:DISM {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            cmd.exe /c exit 0 | Out-Null
            @(
                'Windows Explorer Reported Size of Component Store : 8.50 GB'
                'Actual Size of Component Store : 7.00 GB'
                'Shared with Windows : 5.00 GB'
                'Backups and Disabled Features : 1.25 GB'
                'Cache and Temporary Data : 512 MB'
                'Number of Reclaimable Packages : 3'
                'Component Store Cleanup Recommended : Yes'
            )
        }

        $analysis = Get-ComponentStoreAnalysis

        $analysis.ExplorerReportedSizeMB | Should -Be 8704
        $analysis.ActualSizeMB | Should -Be 7168
        $analysis.SharedWithWindowsMB | Should -Be 5120
        $analysis.BackupsDisabledFeaturesMB | Should -Be 1280
        $analysis.CacheTemporaryDataMB | Should -Be 512
        $analysis.CleanupDeltaMB | Should -Be 1792
        $analysis.ExplorerActualDeltaMB | Should -Be 1536
        $analysis.ReclaimablePackages | Should -Be 3
        $analysis.CleanupRecommended | Should -BeTrue
    }

    It 'resolves DISM repair sources from mounted media and image files' {
        $mountedRoot = Join-Path $TestDrive 'MountedWindows'
        New-Item -Path (Join-Path $mountedRoot 'Windows\WinSxS') -ItemType Directory -Force | Out-Null

        $mountedSpec = Resolve-DismRepairSource -Path $mountedRoot
        $mountedSpec.SourceType | Should -Be 'MountedWindowsImage'
        $mountedSpec.SourceArgument | Should -Be (Join-Path $mountedRoot 'Windows')

        $isoRoot = Join-Path $TestDrive 'IsoRoot'
        New-Item -Path (Join-Path $isoRoot 'sources') -ItemType Directory -Force | Out-Null
        $esdPath = Join-Path $isoRoot 'sources\install.esd'
        Set-Content -LiteralPath $esdPath -Value 'mock esd'

        $isoSpec = Resolve-DismRepairSource -Path $isoRoot
        $isoSpec.SourceType | Should -Be 'ESD'
        $isoSpec.SourceArgument | Should -Be "ESD:${esdPath}:1"

        { Resolve-DismRepairSource -Path (Join-Path $TestDrive 'missing.wim') } | Should -Throw '*does not exist*'
    }

    It 'builds DISM RestoreHealth arguments with source and limit access' {
        $wimPath = Join-Path $TestDrive 'install.wim'
        Set-Content -LiteralPath $wimPath -Value 'mock wim'

        $plan = Get-DismRestoreHealthPlan -DismSource $wimPath -DismLimitAccess

        $plan.Arguments | Should -Contain '/Online'
        $plan.Arguments | Should -Contain '/Cleanup-Image'
        $plan.Arguments | Should -Contain '/RestoreHealth'
        $plan.Arguments | Should -Contain "/Source:WIM:${wimPath}:1"
        $plan.Arguments | Should -Contain '/LimitAccess'
        $plan.Source.SourceType | Should -Be 'WIM'
    }

    It 'passes DISM RestoreHealth source arguments through mocked DISM process' {
        $wimPath = Join-Path $TestDrive 'install.wim'
        Set-Content -LiteralPath $wimPath -Value 'mock wim'
        $script:DismCalls = @()

        function global:DISM {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $script:DismCalls += ,@($Arguments)
            cmd.exe /c exit 0 | Out-Null

            if ($Arguments -contains '/ScanHealth') {
                return @('The component store is repairable.')
            }

            if ($Arguments -contains '/AnalyzeComponentStore') {
                return @(
                    'Actual Size of Component Store : 6.00 GB'
                    'Backups and Disabled Features : 256 MB'
                    'Cache and Temporary Data : 128 MB'
                    'Number of Reclaimable Packages : 0'
                    'Component Store Cleanup Recommended : No'
                )
            }

            return @('OK')
        }

        Invoke-DISM -DismSource $wimPath -DismLimitAccess

        $restoreCall = @($script:DismCalls | Where-Object { $_ -contains '/RestoreHealth' })[0]
        $restoreCall | Should -Contain '/Online'
        $restoreCall | Should -Contain '/Cleanup-Image'
        $restoreCall | Should -Contain '/RestoreHealth'
        $restoreCall | Should -Contain "/Source:WIM:${wimPath}:1"
        $restoreCall | Should -Contain '/LimitAccess'
    }

    It 'parses Windows Update log timeline entries with redaction' {
        $originalUserName = $env:USERNAME
        $originalComputerName = $env:COMPUTERNAME
        try {
            $env:USERNAME = 'Alice'
            $env:COMPUTERNAME = 'DESKTOP-TEST'
            $line = '2026/06/29 12:34:56.1234567 1234 5678 Agent WARNING: Download failed with 0x80240016 for Alice on DESKTOP-TEST'

            $entry = ConvertTo-WULogTimelineEntry -Line $line -Source '%WINDIR%\WindowsUpdate.log' -LineNumber 17

            $entry.Timestamp | Should -Not -BeNullOrEmpty
            $entry.Component | Should -Be 'Agent'
            $entry.Level | Should -Be 'Error'
            $entry.Code | Should -Be '0x80240016'
            $entry.Message | Should -Not -Match 'Alice|DESKTOP-TEST'
            $entry.SourceFile | Should -Be '%WINDIR%\WindowsUpdate.log'
            $entry.Line | Should -Be 17
        }
        finally {
            $env:USERNAME = $originalUserName
            $env:COMPUTERNAME = $originalComputerName
        }
    }

    It 'summarizes Windows Update log timelines by level and code' {
        $timeline = @(
            [PSCustomObject]@{ Level = 'Error'; Code = '0x80240016'; SourceFile = 'WindowsUpdate.log' },
            [PSCustomObject]@{ Level = 'Error'; Code = '0x80240016'; SourceFile = 'WindowsUpdate.log' },
            [PSCustomObject]@{ Level = 'Warning'; Code = $null; SourceFile = 'WindowsUpdate_ETW.log' }
        )

        $summary = Get-WULogTimelineSummary -Timeline $timeline

        $summary.EntryCount | Should -Be 3
        $summary.ErrorCount | Should -Be 2
        $summary.WarningCount | Should -Be 1
        $summary.Sources | Should -Contain 'WindowsUpdate.log'
        $summary.Sources | Should -Contain 'WindowsUpdate_ETW.log'
        $summary.TopCodes[0].Code | Should -Be '0x80240016'
        $summary.TopCodes[0].Count | Should -Be 2
    }

    It 'parses CLI option values for spaced and inline assignments' {
        $arguments = @(
            '-JsonReport', 'C:\Temp\repair.json',
            '-SupportBundle=C:\Temp\support.zip',
            '-DismSource', 'D:\sources\install.wim'
        )

        Get-CommandLineOptionValue -Arguments $arguments -Name '-JsonReport' | Should -Be 'C:\Temp\repair.json'
        Get-CommandLineOptionValue -Arguments $arguments -Name '-SupportBundle' | Should -Be 'C:\Temp\support.zip'
        Get-CommandLineOptionValue -Arguments $arguments -Name '-DismSource' | Should -Be 'D:\sources\install.wim'
        { Get-CommandLineOptionValue -Arguments @('-JsonReport') -Name '-JsonReport' } | Should -Throw '*requires a path value*'
    }

    It 'resolves repair phase selection for full targeted and quick runs' {
        $full = Resolve-WURepairPhaseSelection
        $full.SelectiveMode | Should -BeFalse
        $full.RepairServices | Should -BeTrue
        $full.RepairDISM | Should -BeTrue
        $full.RepairSFC | Should -BeTrue
        $full.RepairServicingStack | Should -BeFalse

        $targeted = Resolve-WURepairPhaseSelection -RepairStore -RepairDLLs
        $targeted.SelectiveMode | Should -BeTrue
        $targeted.RepairStore | Should -BeTrue
        $targeted.RepairDLLs | Should -BeTrue
        $targeted.RepairServices | Should -BeFalse
        $targeted.RepairDISM | Should -BeFalse

        $quick = Resolve-WURepairPhaseSelection -QuickMode
        $quick.SelectiveMode | Should -BeFalse
        $quick.RepairServices | Should -BeTrue
        $quick.RepairDISM | Should -BeFalse
        $quick.RepairSFC | Should -BeFalse
    }

    It 'keeps release version strings consistent across tracked docs' {
        $versionMatch = [regex]::Match($script:Content, "Version\s*=\s*'(?<Version>\d+\.\d+\.\d+)'")
        $versionMatch.Success | Should -BeTrue
        $version = $versionMatch.Groups['Version'].Value

        $readmePath = Join-Path $script:RepoRoot 'README.md'
        $readme = Get-Content -LiteralPath $readmePath -Raw
        $readme | Should -Match ("Version-{0}-orange" -f [regex]::Escape($version))
        $readme | Should -Match ("### v{0}" -f [regex]::Escape($version))

        $changelogPath = Join-Path $script:RepoRoot 'CHANGELOG.md'
        if (Test-Path -LiteralPath $changelogPath) {
            $changelog = Get-Content -LiteralPath $changelogPath -Raw
            $changelog | Should -Match ("## \[v{0}\]" -f [regex]::Escape($version))
        }
    }

    It 'wires optional package and remediation artifact parse validation' {
        $localChecksPath = Join-Path $script:RepoRoot 'Invoke-LocalChecks.ps1'
        $localChecks = Get-Content -LiteralPath $localChecksPath -Raw

        $localChecks | Should -Match '\$artifactPatterns'
        $localChecks | Should -Match 'Test-ModuleManifest'
        $localChecks | Should -Match 'ParseFile'
        $localChecks | Should -Match 'ps1xml'
        $localChecks | Should -Match 'Intune'
    }

    It 'validates module manifest metadata and exported wrappers' {
        $manifestPath = Join-Path $script:RepoRoot 'WURepair.psd1'
        Test-Path -LiteralPath $manifestPath | Should -BeTrue

        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.Name | Should -Be 'WURepair'
        $manifest.Version.ToString() | Should -Match '^\d+\.\d+\.\d+'
        $manifest.PowerShellVersion.ToString() | Should -Be '5.1'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Invoke-WURepair'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Repair-WURepairDism'
        $manifest.PrivateData.PSData.Tags | Should -Contain 'WindowsUpdate'
        $manifest.PrivateData.PSData.LicenseUri | Should -Match 'LICENSE'
    }

    It 'wires release packaging to local checks signing catalogs and checksums' {
        $packageScriptPath = Join-Path $script:RepoRoot 'tools\Build-WURepairPackage.ps1'
        Test-Path -LiteralPath $packageScriptPath | Should -BeTrue

        $packageScript = Get-Content -LiteralPath $packageScriptPath -Raw
        $packageScript | Should -Match 'Invoke-LocalChecks\.ps1'
        $packageScript | Should -Match 'Set-AuthenticodeSignature'
        $packageScript | Should -Match 'New-FileCatalog'
        $packageScript | Should -Match 'SHA256SUMS\.txt'
        $packageScript | Should -Match 'WURepair-release-v'
        $packageScript | Should -Match 'WURepair-module'
    }
}
