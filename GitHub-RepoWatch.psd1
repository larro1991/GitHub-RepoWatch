@{
    # Module manifest for GitHub-RepoWatch

    # Script module associated with this manifest
    RootModule        = 'GitHub-RepoWatch.psm1'

    # Version number
    ModuleVersion     = '1.0.0'

    # Unique ID
    GUID              = 'd0e1f2a3-7b68-4de4-c5f6-1b2c3d4e5f67'

    # Author
    Author            = 'Larry Roberts, Independent Consultant'

    # Company
    CompanyName       = 'Independent'

    # Copyright
    Copyright         = '(c) 2026 Larry Roberts. All rights reserved.'

    # Description
    Description       = 'Monitor your GitHub repos and PSGallery packages for new issues, comments, PRs, stars, and download stats. Get email digests on a schedule.'

    # Minimum PowerShell version
    PowerShellVersion = '5.1'

    # Compatible PowerShell editions
    CompatiblePSEditions = @('Desktop', 'Core')

    # Functions to export
    FunctionsToExport = @(
        'Get-RepoActivity'
        'Get-PSGalleryStats'
        'Send-ActivityDigest'
        'Invoke-RepoWatch'
        'Register-RepoWatchTask'
    )

    # Cmdlets to export (none)
    CmdletsToExport   = @()

    # Variables to export (none)
    VariablesToExport  = @()

    # Aliases to export (none)
    AliasesToExport    = @()

    # Private data with PSGallery metadata
    PrivateData       = @{
        PSData = @{
            Tags         = @('GitHub', 'Monitoring', 'Issues', 'PSGallery', 'Email', 'Digest', 'OpenSource', 'Automation')
            ProjectUri   = 'https://github.com/larro1991/GitHub-RepoWatch'
            LicenseUri   = 'https://github.com/larro1991/GitHub-RepoWatch/blob/master/LICENSE'
            ReleaseNotes = 'Initial release: GitHub repo activity monitoring with email digest support.'
        }
    }
}
