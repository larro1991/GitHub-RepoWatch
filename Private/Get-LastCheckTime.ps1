function Get-LastCheckTime {
    <#
    .SYNOPSIS
        Manages the state file for tracking between RepoWatch runs.
    .DESCRIPTION
        Reads or writes the JSON state file that stores the last check timestamp,
        star/fork counts per repo, and PSGallery download counts. This enables
        delta tracking between runs so the digest shows only changes.
    .PARAMETER StatePath
        Path to the state JSON file.
    .PARAMETER Owner
        GitHub owner/username for namespacing state data.
    .PARAMETER Write
        Switch to enable write mode. When set, updates the state file with Data.
    .PARAMETER Data
        Hashtable of data to write to state. Used with -Write switch.
    .EXAMPLE
        $state = Get-LastCheckTime -StatePath $path -Owner "larro1991"
    .EXAMPLE
        Get-LastCheckTime -StatePath $path -Owner "larro1991" -Write -Data $newState
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StatePath = (Join-Path $env:USERPROFILE '.repowatch\state.json'),

        [Parameter()]
        [string]$Owner,

        [Parameter()]
        [switch]$Write,

        [Parameter()]
        [hashtable]$Data
    )

    # Ensure the directory exists
    $stateDir = Split-Path -Path $StatePath -Parent
    if (-not (Test-Path -Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    if ($Write) {
        # Write mode: update state file with provided data
        if (-not $Data) {
            Write-Error 'Data parameter is required when using -Write switch.'
            return
        }

        $state = @{}

        # Load existing state if file exists
        if (Test-Path -Path $StatePath) {
            try {
                $existingContent = Get-Content -Path $StatePath -Raw -Encoding UTF8
                if ($existingContent) {
                    $existingState = $existingContent | ConvertFrom-Json
                    # Convert PSObject to hashtable
                    foreach ($prop in $existingState.PSObject.Properties) {
                        $state[$prop.Name] = $prop.Value
                    }
                }
            }
            catch {
                Write-Warning "Could not parse existing state file. Creating new one."
                $state = @{}
            }
        }

        # Merge in new data
        foreach ($key in $Data.Keys) {
            $state[$key] = $Data[$key]
        }

        # Write state file with UTF-8 BOM encoding
        $jsonContent = $state | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText(
            $StatePath,
            $jsonContent,
            [System.Text.UTF8Encoding]::new($true)
        )

        Write-Verbose "State file updated: $StatePath"
        return
    }
    else {
        # Read mode: return current state
        if (-not (Test-Path -Path $StatePath)) {
            Write-Verbose "State file not found at $StatePath. Returning defaults."
            return [PSCustomObject]@{
                last_check = $null
                repos      = @{}
                psgallery  = @{}
            }
        }

        try {
            $content = Get-Content -Path $StatePath -Raw -Encoding UTF8
            if (-not $content) {
                return [PSCustomObject]@{
                    last_check = $null
                    repos      = @{}
                    psgallery  = @{}
                }
            }

            $stateObj = $content | ConvertFrom-Json

            # Ensure expected properties exist
            if (-not ($stateObj.PSObject.Properties.Name -contains 'last_check')) {
                $stateObj | Add-Member -NotePropertyName 'last_check' -NotePropertyValue $null
            }
            if (-not ($stateObj.PSObject.Properties.Name -contains 'repos')) {
                $stateObj | Add-Member -NotePropertyName 'repos' -NotePropertyValue ([PSCustomObject]@{})
            }
            if (-not ($stateObj.PSObject.Properties.Name -contains 'psgallery')) {
                $stateObj | Add-Member -NotePropertyName 'psgallery' -NotePropertyValue ([PSCustomObject]@{})
            }

            return $stateObj
        }
        catch {
            Write-Warning "Failed to parse state file: $_"
            return [PSCustomObject]@{
                last_check = $null
                repos      = @{}
                psgallery  = @{}
            }
        }
    }
}
