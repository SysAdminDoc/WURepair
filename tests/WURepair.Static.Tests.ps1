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
            'Get-ComponentStoreAnalysis'
        )
    }

    BeforeEach {
        $Script:Config = @{
            LogPath                            = Join-Path $TestDrive 'WURepair.log'
            TempPath                           = Join-Path $TestDrive 'Temp'
            Unattended                         = $true
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
            $result = New-WUSupportBundle -Path $bundlePath -JsonReportPath $jsonPath -ModeLabel 'Test' -OverallStatus 'Success' -ExitCode 0 -PhaseResults @()

            Test-Path -LiteralPath $result | Should -BeTrue
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($result)
            try {
                $entryNames = @($zip.Entries | Select-Object -ExpandProperty FullName)
                $entryNames | Should -Contain 'manifest.json'
                $entryNames | Should -Contain 'WURepair.log'
                $entryNames | Should -Contain 'WURepair-report.json'
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
}
