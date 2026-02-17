# GitHub-RepoWatch Module Loader
# Dot-sources all private and public function files, then exports public functions.

$ErrorActionPreference = 'Stop'

# Get module root path
$moduleRoot = $PSScriptRoot

# Dot-source private functions first (helpers used by public functions)
$privatePath = Join-Path -Path $moduleRoot -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    $privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -File
    foreach ($file in $privateFiles) {
        try {
            . $file.FullName
            Write-Verbose "Loaded private function: $($file.BaseName)"
        }
        catch {
            Write-Error "Failed to load private function $($file.FullName): $_"
        }
    }
}

# Dot-source public functions
$publicPath = Join-Path -Path $moduleRoot -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -File
    foreach ($file in $publicFiles) {
        try {
            . $file.FullName
            Write-Verbose "Loaded public function: $($file.BaseName)"
        }
        catch {
            Write-Error "Failed to load public function $($file.FullName): $_"
        }
    }
}

# Export only public functions
$publicFunctions = @(
    'Get-RepoActivity'
    'Get-PSGalleryStats'
    'Send-ActivityDigest'
    'Invoke-RepoWatch'
    'Register-RepoWatchTask'
)

Export-ModuleMember -Function $publicFunctions
