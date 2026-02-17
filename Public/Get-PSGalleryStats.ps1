function Get-PSGalleryStats {
    <#
    .SYNOPSIS
        Checks PowerShell Gallery for download stats on published modules.
    .DESCRIPTION
        Queries the PowerShell Gallery for modules by a given author or by name.
        Compares current download counts to previously stored state to calculate
        download deltas. Returns version, download count, change, and gallery URL.
    .PARAMETER Author
        PSGallery author name to search for. Defaults to the Owner parameter if used
        via Invoke-RepoWatch.
    .PARAMETER ModuleNames
        Specific module names to check. When not specified, auto-discovers modules
        by the Author via Find-Module.
    .PARAMETER StatePath
        Path to the state JSON file for tracking download count changes.
    .EXAMPLE
        Get-PSGalleryStats -Author "LarryRoberts"
    .EXAMPLE
        Get-PSGalleryStats -ModuleNames "AD-SecurityAudit","M365-SecurityBaseline"
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Author,

        [Parameter()]
        [string[]]$ModuleNames,

        [Parameter()]
        [string]$StatePath = (Join-Path $env:USERPROFILE '.repowatch\state.json')
    )

    if (-not $Author -and -not $ModuleNames) {
        Write-Error 'You must specify either -Author or -ModuleNames.'
        return
    }

    # Load previous state for download delta comparison
    $state = Get-LastCheckTime -StatePath $StatePath

    # Discover modules
    $modules = @()

    if ($ModuleNames -and $ModuleNames.Count -gt 0) {
        foreach ($modName in $ModuleNames) {
            try {
                $found = Find-Module -Name $modName -ErrorAction Stop
                if ($found) { $modules += $found }
            }
            catch {
                Write-Warning "Module '$modName' not found on PowerShell Gallery."
            }
        }
    }
    elseif ($Author) {
        try {
            Write-Verbose "Searching PSGallery for modules by author: $Author"
            $modules = @(Find-Module -Filter $Author -ErrorAction Stop |
                Where-Object { $_.Author -like "*$Author*" })
        }
        catch {
            Write-Warning "Failed to search PSGallery for author '$Author': $_"
            return @()
        }
    }

    if ($modules.Count -eq 0) {
        Write-Verbose "No modules found on PowerShell Gallery."
        return @()
    }

    Write-Verbose "Found $($modules.Count) module(s) on PowerShell Gallery."

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($mod in $modules) {
        $modName = $mod.Name
        $totalDownloads = [int]$mod.AdditionalMetadata.downloadCount

        # If downloadCount is not available via AdditionalMetadata, try the property
        if ($totalDownloads -eq 0 -and $mod.PSObject.Properties.Name -contains 'DownloadCount') {
            $totalDownloads = [int]$mod.DownloadCount
        }

        # Calculate download delta from previous state
        $prevDownloads = 0
        if ($state.psgallery -and $state.psgallery.PSObject.Properties.Name -contains $modName) {
            $prevData = $state.psgallery.$modName
            if ($prevData.PSObject.Properties.Name -contains 'downloads') {
                $prevDownloads = [int]$prevData.downloads
            }
        }

        $downloadChange = if ($prevDownloads -gt 0) { $totalDownloads - $prevDownloads } else { 0 }

        $galleryUrl = "https://www.powershellgallery.com/packages/$modName"

        $publishedDate = $null
        if ($mod.PSObject.Properties.Name -contains 'PublishedDate' -and $mod.PublishedDate) {
            $publishedDate = $mod.PublishedDate
        }
        elseif ($mod.AdditionalMetadata -and $mod.AdditionalMetadata.PSObject.Properties.Name -contains 'published') {
            $publishedDate = [datetime]$mod.AdditionalMetadata.published
        }

        $statObj = [PSCustomObject]@{
            ModuleName      = $modName
            Version         = $mod.Version.ToString()
            TotalDownloads  = $totalDownloads
            DownloadChange  = $downloadChange
            PublishedDate   = $publishedDate
            GalleryUrl      = $galleryUrl
            Description     = $mod.Description
            HasNewDownloads = ($downloadChange -gt 0)
        }

        $results.Add($statObj)
    }

    return $results.ToArray()
}
