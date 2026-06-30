@{
    RootModule        = 'WURepair.psm1'
    ModuleVersion     = '2.21.0'
    GUID              = '4d2cbad8-1eb2-4a0d-8b94-ccb86fb723ce'
    Author            = 'SysAdminDoc'
    CompanyName       = 'SysAdminDoc'
    Copyright         = '(c) 2026 SysAdminDoc. All rights reserved.'
    Description       = 'Windows Update repair and diagnostics wrapper for WURepair.ps1.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-WURepair',
        'Repair-WURepairServices',
        'Repair-WURepairDlls',
        'Repair-WURepairStore',
        'Repair-WURepairDism',
        'Repair-WURepairSfc',
        'Repair-WURepairNetwork',
        'Repair-WURepairWaaS',
        'Repair-WURepairDelivery',
        'Repair-WURepairServicingStack'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    FileList          = @(
        'WURepair.ps1',
        'WURepair.psm1',
        'WURepair.psd1',
        'README.md',
        'LICENSE',
        'CHANGELOG.md'
    )
    PrivateData       = @{
        PSData = @{
            Tags         = @('WindowsUpdate', 'Repair', 'Diagnostics', 'RMM', 'Intune', 'WSUS', 'DISM')
            LicenseUri   = 'https://github.com/SysAdminDoc/WURepair/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/SysAdminDoc/WURepair'
            ReleaseNotes = 'Adds module metadata and local release packaging with checksums and optional signing.'
        }
    }
}
