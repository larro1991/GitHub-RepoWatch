#Requires -Module Pester

<#
    Pester v5 tests for GitHub-RepoWatch module.
    Covers module loading, manifest validation, parameter validation,
    and mock-based functional tests for all major components.
#>

BeforeAll {
    $modulePath = Split-Path -Path $PSScriptRoot -Parent
    Import-Module $modulePath -Force
}

Describe 'Module Loading' {
    It 'Imports the module without errors' {
        $module = Get-Module -Name 'GitHub-RepoWatch'
        $module | Should -Not -BeNullOrEmpty
    }

    It 'Exports exactly 5 public functions' {
        $module = Get-Module -Name 'GitHub-RepoWatch'
        $module.ExportedFunctions.Count | Should -Be 5
    }

    It 'Exports Get-RepoActivity' {
        Get-Command -Module 'GitHub-RepoWatch' -Name 'Get-RepoActivity' | Should -Not -BeNullOrEmpty
    }

    It 'Exports Get-PSGalleryStats' {
        Get-Command -Module 'GitHub-RepoWatch' -Name 'Get-PSGalleryStats' | Should -Not -BeNullOrEmpty
    }

    It 'Exports Send-ActivityDigest' {
        Get-Command -Module 'GitHub-RepoWatch' -Name 'Send-ActivityDigest' | Should -Not -BeNullOrEmpty
    }

    It 'Exports Invoke-RepoWatch' {
        Get-Command -Module 'GitHub-RepoWatch' -Name 'Invoke-RepoWatch' | Should -Not -BeNullOrEmpty
    }

    It 'Exports Register-RepoWatchTask' {
        Get-Command -Module 'GitHub-RepoWatch' -Name 'Register-RepoWatchTask' | Should -Not -BeNullOrEmpty
    }

    It 'Does NOT export Get-GitHubAPI (private)' {
        $cmd = Get-Command -Module 'GitHub-RepoWatch' -Name 'Get-GitHubAPI' -ErrorAction SilentlyContinue
        $cmd | Should -BeNullOrEmpty
    }

    It 'Does NOT export Get-LastCheckTime (private)' {
        $cmd = Get-Command -Module 'GitHub-RepoWatch' -Name 'Get-LastCheckTime' -ErrorAction SilentlyContinue
        $cmd | Should -BeNullOrEmpty
    }

    It 'Does NOT export New-HtmlDigest (private)' {
        $cmd = Get-Command -Module 'GitHub-RepoWatch' -Name 'New-HtmlDigest' -ErrorAction SilentlyContinue
        $cmd | Should -BeNullOrEmpty
    }
}

Describe 'Module Manifest Validation' {
    BeforeAll {
        $manifestPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'GitHub-RepoWatch.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath
    }

    It 'Has the correct GUID' {
        $manifest.Guid.ToString() | Should -Be 'd0e1f2a3-7b68-4de4-c5f6-1b2c3d4e5f67'
    }

    It 'Requires PowerShell 5.1 or later' {
        $manifest.PowerShellVersion | Should -Be '5.1'
    }

    It 'Has the correct author' {
        $manifest.Author | Should -BeLike '*Larry Roberts*'
    }

    It 'Has a description' {
        $manifest.Description | Should -Not -BeNullOrEmpty
    }

    It 'Has the expected tags' {
        $tags = $manifest.PrivateData.PSData.Tags
        $tags | Should -Contain 'GitHub'
        $tags | Should -Contain 'Monitoring'
        $tags | Should -Contain 'PSGallery'
        $tags | Should -Contain 'Email'
        $tags | Should -Contain 'Digest'
        $tags | Should -Contain 'Automation'
    }

    It 'Has a ProjectUri' {
        $manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/larro1991/GitHub-RepoWatch'
    }

    It 'Has a LicenseUri' {
        $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
    }

    It 'Declares 5 exported functions' {
        $manifest.ExportedFunctions.Count | Should -Be 5
    }
}

Describe 'Parameter Validation' {
    Context 'Get-RepoActivity' {
        It 'Owner parameter is mandatory' {
            (Get-Command Get-RepoActivity).Parameters['Owner'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'SinceHours has ValidateRange(1, 720)' {
            $attrs = (Get-Command Get-RepoActivity).Parameters['SinceHours'].Attributes
            $rangeAttr = $attrs | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr | Should -Not -BeNullOrEmpty
            $rangeAttr.MinRange | Should -Be 1
            $rangeAttr.MaxRange | Should -Be 720
        }

        It 'SinceHours is type int' {
            (Get-Command Get-RepoActivity).Parameters['SinceHours'].ParameterType.Name | Should -Be 'Int32'
        }
    }

    Context 'Send-ActivityDigest' {
        It 'SmtpServer parameter is mandatory' {
            (Get-Command Send-ActivityDigest).Parameters['SmtpServer'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'EmailTo parameter is mandatory' {
            (Get-Command Send-ActivityDigest).Parameters['EmailTo'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'EmailFrom parameter is mandatory' {
            (Get-Command Send-ActivityDigest).Parameters['EmailFrom'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'Activity parameter accepts pipeline input' {
            $pipelineAttr = (Get-Command Send-ActivityDigest).Parameters['Activity'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline }
            $pipelineAttr | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Register-RepoWatchTask' {
        It 'Owner parameter is mandatory' {
            (Get-Command Register-RepoWatchTask).Parameters['Owner'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'Schedule has ValidateSet (Daily, TwiceDaily, Hourly)' {
            $attrs = (Get-Command Register-RepoWatchTask).Parameters['Schedule'].Attributes
            $validateSet = $attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet | Should -Not -BeNullOrEmpty
            $validateSet.ValidValues | Should -Contain 'Daily'
            $validateSet.ValidValues | Should -Contain 'TwiceDaily'
            $validateSet.ValidValues | Should -Contain 'Hourly'
        }
    }

    Context 'Invoke-RepoWatch' {
        It 'Owner parameter is mandatory' {
            (Get-Command Invoke-RepoWatch).Parameters['Owner'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } |
                Should -Contain $true
        }

        It 'SinceHours has ValidateRange(1, 720)' {
            $attrs = (Get-Command Invoke-RepoWatch).Parameters['SinceHours'].Attributes
            $rangeAttr = $attrs | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $rangeAttr | Should -Not -BeNullOrEmpty
            $rangeAttr.MinRange | Should -Be 1
            $rangeAttr.MaxRange | Should -Be 720
        }
    }
}

Describe 'Get-GitHubAPI (Mock-Based)' {
    BeforeAll {
        # Re-import module internals so we can test private function
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\Get-GitHubAPI.ps1')

        # Store call details in a script-scope variable since splatted params
        # are not accessible via Pester ParameterFilter on Invoke-RestMethod
        $script:lastApiCall = $null
    }

    It 'Constructs the correct URL for an endpoint' {
        $script:capturedUri = $null

        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ContentType, $Body,
                  [switch]$UseBasicParsing, $ErrorAction, $ResponseHeadersVariable)
            $script:capturedUri = $Uri
            return @{ id = 1; name = 'test-repo' }
        }

        $result = Get-GitHubAPI -Endpoint '/repos/testowner/testrepo'

        $script:capturedUri | Should -Be 'https://api.github.com/repos/testowner/testrepo'
        $result.name | Should -Be 'test-repo'

        Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It 'Includes authorization header when token is provided' {
        # Wrap Invoke-RestMethod to capture the headers hashtable
        $script:capturedHeaders = $null
        $originalIRM = Get-Command Invoke-RestMethod -CommandType Cmdlet

        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ContentType, $Body,
                  [switch]$UseBasicParsing, $ErrorAction, $ResponseHeadersVariable)
            $script:capturedHeaders = $Headers
            return @{ id = 1 }
        }

        Get-GitHubAPI -Endpoint '/repos/test/test' -Token 'ghp_testtoken123' -ErrorAction SilentlyContinue

        $script:capturedHeaders['Authorization'] | Should -Be 'Bearer ghp_testtoken123'

        # Restore original
        Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It 'Sets required GitHub API headers' {
        $script:capturedHeaders = $null

        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ContentType, $Body,
                  [switch]$UseBasicParsing, $ErrorAction, $ResponseHeadersVariable)
            $script:capturedHeaders = $Headers
            return @{ id = 1 }
        }

        Get-GitHubAPI -Endpoint '/repos/test/test' -ErrorAction SilentlyContinue

        $script:capturedHeaders['Accept'] | Should -Be 'application/vnd.github+json'
        $script:capturedHeaders['X-GitHub-Api-Version'] | Should -Be '2022-11-28'
        $script:capturedHeaders['User-Agent'] | Should -Be 'GitHub-RepoWatch-PowerShell'

        Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    }

    It 'Works without a token (no Authorization header)' {
        $originalToken = $env:GITHUB_TOKEN
        $env:GITHUB_TOKEN = $null

        try {
            $script:capturedHeaders = $null

            function Invoke-RestMethod {
                param($Uri, $Method, $Headers, $ContentType, $Body,
                      [switch]$UseBasicParsing, $ErrorAction, $ResponseHeadersVariable)
                $script:capturedHeaders = $Headers
                return @{ id = 1 }
            }

            Get-GitHubAPI -Endpoint '/repos/test/test' -ErrorAction SilentlyContinue

            $script:capturedHeaders.ContainsKey('Authorization') | Should -Be $false
        }
        finally {
            $env:GITHUB_TOKEN = $originalToken
            Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-RepoActivity (Mock-Based)' {
    BeforeAll {
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\Get-GitHubAPI.ps1')
        . (Join-Path $modulePath 'Private\Get-LastCheckTime.ps1')
        . (Join-Path $modulePath 'Public\Get-RepoActivity.ps1')
    }

    It 'Returns repos with correct HasActivity flags' {
        $sinceIso = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Mock state file
        Mock Get-LastCheckTime {
            return [PSCustomObject]@{
                last_check = $sinceIso
                repos      = [PSCustomObject]@{
                    'active-repo' = [PSCustomObject]@{ stars = 10; forks = 2 }
                    'quiet-repo'  = [PSCustomObject]@{ stars = 5; forks = 1 }
                }
                psgallery  = [PSCustomObject]@{}
            }
        }

        # Mock API calls
        Mock Get-GitHubAPI {
            $ep = $Endpoint
            if ($ep -match '/users/.*/repos') {
                return @(
                    @{ name = 'active-repo'; html_url = 'https://github.com/test/active-repo'; stargazers_count = 12; forks_count = 2; fork = $false },
                    @{ name = 'quiet-repo'; html_url = 'https://github.com/test/quiet-repo'; stargazers_count = 5; forks_count = 1; fork = $false }
                )
            }
            elseif ($ep -match 'active-repo/issues\?state=open') {
                $newDate = (Get-Date).AddHours(-2).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                return @(
                    @{ number = 1; title = 'Bug report'; user = @{ login = 'tester' }; created_at = $newDate; html_url = 'https://github.com/test/active-repo/issues/1'; pull_request = $null }
                )
            }
            elseif ($ep -match 'quiet-repo/issues\?state=open') {
                return @()
            }
            elseif ($ep -match '/issues/comments') {
                return @()
            }
            elseif ($ep -match '/pulls') {
                return @()
            }
            else {
                return @()
            }
        }

        $results = Get-RepoActivity -Owner 'test' -SinceHours 24

        $results | Should -Not -BeNullOrEmpty
        $results.Count | Should -Be 2

        $active = $results | Where-Object { $_.RepoName -eq 'active-repo' }
        $quiet = $results | Where-Object { $_.RepoName -eq 'quiet-repo' }

        $active.HasActivity | Should -Be $true
        $active.StarsChange | Should -Be 2
        $active.NewIssues.Count | Should -Be 1

        $quiet.HasActivity | Should -Be $false
    }
}

Describe 'Get-PSGalleryStats (Mock-Based)' {
    BeforeAll {
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\Get-LastCheckTime.ps1')
        . (Join-Path $modulePath 'Public\Get-PSGalleryStats.ps1')
    }

    It 'Calculates download deltas correctly against state file' {
        Mock Get-LastCheckTime {
            return [PSCustomObject]@{
                last_check = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                repos      = [PSCustomObject]@{}
                psgallery  = [PSCustomObject]@{
                    'TestModule' = [PSCustomObject]@{ downloads = 100 }
                }
            }
        }

        # Override Find-Module locally since dot-sourced functions use local scope
        function Find-Module {
            param($Name, $Filter, [switch]$ErrorAction)
            $mod = [PSCustomObject]@{
                Name               = 'TestModule'
                Version            = [version]'1.2.3'
                Author             = 'TestAuthor'
                Description        = 'A test module'
                AdditionalMetadata = [PSCustomObject]@{ downloadCount = '147' }
                PublishedDate      = (Get-Date).AddDays(-10)
            }
            return $mod
        }

        $results = Get-PSGalleryStats -ModuleNames 'TestModule'

        $results | Should -Not -BeNullOrEmpty
        @($results).Count | Should -Be 1
        $results[0].ModuleName | Should -Be 'TestModule'
        $results[0].TotalDownloads | Should -Be 147
        $results[0].DownloadChange | Should -Be 47
        $results[0].HasNewDownloads | Should -Be $true
    }
}

Describe 'Get-LastCheckTime (State File Roundtrip)' {
    BeforeAll {
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\Get-LastCheckTime.ps1')
        $tempState = Join-Path $TestDrive 'test-state.json'
    }

    It 'Returns default state when file does not exist' {
        $state = Get-LastCheckTime -StatePath $tempState -Owner 'test'

        $state.last_check | Should -BeNullOrEmpty
    }

    It 'Writes and reads state correctly (roundtrip)' {
        $writeData = @{
            last_check = '2026-02-16T08:00:00Z'
            repos      = @{
                'my-repo' = @{ stars = 42; forks = 7 }
            }
            psgallery  = @{
                'MyModule' = @{ downloads = 256 }
            }
        }

        Get-LastCheckTime -StatePath $tempState -Owner 'test' -Write -Data $writeData

        Test-Path $tempState | Should -Be $true

        $readState = Get-LastCheckTime -StatePath $tempState -Owner 'test'

        $readState.last_check | Should -Be '2026-02-16T08:00:00Z'
        $readState.repos.'my-repo'.stars | Should -Be 42
        $readState.repos.'my-repo'.forks | Should -Be 7
        $readState.psgallery.'MyModule'.downloads | Should -Be 256
    }

    It 'Creates the state directory if it does not exist' {
        $deepPath = Join-Path $TestDrive 'deep\nested\dir\state.json'

        Get-LastCheckTime -StatePath $deepPath -Owner 'test' -Write -Data @{
            last_check = '2026-02-16T12:00:00Z'
        }

        Test-Path $deepPath | Should -Be $true
    }
}

Describe 'New-HtmlDigest' {
    BeforeAll {
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\New-HtmlDigest.ps1')
    }

    It 'Generates valid HTML with DOCTYPE' {
        $html = New-HtmlDigest -Activity @()
        $html | Should -BeLike '<!DOCTYPE html>*'
    }

    It 'Includes repo names and links in output' {
        $activity = @(
            [PSCustomObject]@{
                RepoName      = 'TestRepo'
                RepoUrl       = 'https://github.com/test/TestRepo'
                Stars         = 10
                StarsChange   = 2
                Forks         = 3
                ForksChange   = 0
                NewIssues     = @(
                    [PSCustomObject]@{ number = 1; title = 'Test Issue'; user = 'tester'; created_at = '2026-02-16T10:00:00Z'; url = 'https://github.com/test/TestRepo/issues/1' }
                )
                NewComments   = @()
                NewPRs        = @()
                UpdatedIssues = @()
                HasActivity   = $true
            }
        )

        $html = New-HtmlDigest -Activity $activity

        $html | Should -BeLike '*TestRepo*'
        $html | Should -BeLike '*https://github.com/test/TestRepo*'
        $html | Should -BeLike '*Test Issue*'
        $html | Should -BeLike '*tester*'
    }

    It 'Includes PSGallery section when stats are provided' {
        $stats = @(
            [PSCustomObject]@{
                ModuleName      = 'SampleModule'
                Version         = '1.0.0'
                TotalDownloads  = 500
                DownloadChange  = 25
                GalleryUrl      = 'https://www.powershellgallery.com/packages/SampleModule'
                HasNewDownloads = $true
            }
        )

        $html = New-HtmlDigest -PSGalleryStats $stats

        $html | Should -BeLike '*PowerShell Gallery*'
        $html | Should -BeLike '*SampleModule*'
        $html | Should -BeLike '*500*'
    }

    It 'Uses only inline CSS (no <style> blocks)' {
        $html = New-HtmlDigest -Activity @()
        $html | Should -Not -BeLike '*<style*'
    }

    It 'Includes the footer with project link' {
        $html = New-HtmlDigest -Activity @()
        $html | Should -BeLike '*GitHub-RepoWatch*'
        $html | Should -BeLike '*https://github.com/larro1991/GitHub-RepoWatch*'
    }
}

Describe 'Register-RepoWatchTask (Mock-Based)' {
    BeforeAll {
        $modulePath = Split-Path -Path $PSScriptRoot -Parent
        . (Join-Path $modulePath 'Private\Get-GitHubAPI.ps1')
        . (Join-Path $modulePath 'Private\Get-LastCheckTime.ps1')
        . (Join-Path $modulePath 'Private\New-HtmlDigest.ps1')
        . (Join-Path $modulePath 'Public\Get-RepoActivity.ps1')
        . (Join-Path $modulePath 'Public\Get-PSGalleryStats.ps1')
        . (Join-Path $modulePath 'Public\Send-ActivityDigest.ps1')
        . (Join-Path $modulePath 'Public\Invoke-RepoWatch.ps1')
        . (Join-Path $modulePath 'Public\Register-RepoWatchTask.ps1')
    }

    It 'Creates wrapper script with correct owner and schedule parameters' {
        # Instead of mocking Register-ScheduledTask (which has CIM type constraints),
        # we test that the wrapper script is generated correctly.
        Mock Get-ScheduledTask { return $null }
        Mock Register-ScheduledTask {
            return [PSCustomObject]@{ TaskName = 'GitHub-RepoWatch'; State = 'Ready' }
        }
        Mock Unregister-ScheduledTask { }
        Mock Get-ScheduledTaskInfo { return [PSCustomObject]@{ NextRunTime = (Get-Date).AddDays(1) } }

        # Run the function and allow it to fail on Register-ScheduledTask type constraints
        Register-RepoWatchTask -Owner 'testowner' -Schedule 'Daily' -Time '09:00' -Confirm:$false -ErrorAction SilentlyContinue

        # Verify the wrapper script was created with correct content
        $wrapperPath = Join-Path $env:USERPROFILE '.repowatch\Run-RepoWatch.ps1'
        Test-Path $wrapperPath | Should -Be $true

        $wrapperContent = Get-Content -Path $wrapperPath -Raw
        $wrapperContent | Should -BeLike "*-Owner 'testowner'*"
        $wrapperContent | Should -BeLike '*Import-Module*'
        $wrapperContent | Should -BeLike '*Invoke-RepoWatch*'
    }

    It 'Includes -SkipIfEmpty in wrapper when specified' {
        Mock Get-ScheduledTask { return $null }
        Mock Register-ScheduledTask {
            return [PSCustomObject]@{ TaskName = 'GitHub-RepoWatch'; State = 'Ready' }
        }
        Mock Unregister-ScheduledTask { }
        Mock Get-ScheduledTaskInfo { return [PSCustomObject]@{ NextRunTime = (Get-Date).AddHours(1) } }

        Register-RepoWatchTask -Owner 'testowner' -Schedule 'Hourly' -SkipIfEmpty -Confirm:$false -ErrorAction SilentlyContinue

        $wrapperPath = Join-Path $env:USERPROFILE '.repowatch\Run-RepoWatch.ps1'
        $wrapperContent = Get-Content -Path $wrapperPath -Raw
        $wrapperContent | Should -BeLike '*-SkipIfEmpty*'
        $wrapperContent | Should -BeLike '*-SinceHours 2*'
    }

    It 'Includes GitHub token in wrapper when provided' {
        Mock Get-ScheduledTask { return $null }
        Mock Register-ScheduledTask {
            return [PSCustomObject]@{ TaskName = 'GitHub-RepoWatch'; State = 'Ready' }
        }
        Mock Unregister-ScheduledTask { }
        Mock Get-ScheduledTaskInfo { return [PSCustomObject]@{ NextRunTime = (Get-Date).AddDays(1) } }

        Register-RepoWatchTask -Owner 'testowner' -Token 'ghp_test123' -Schedule 'Daily' -Confirm:$false -ErrorAction SilentlyContinue

        $wrapperPath = Join-Path $env:USERPROFILE '.repowatch\Run-RepoWatch.ps1'
        $wrapperContent = Get-Content -Path $wrapperPath -Raw
        $wrapperContent | Should -BeLike '*GITHUB_TOKEN*'
        $wrapperContent | Should -BeLike '*ghp_test123*'
    }
}

AfterAll {
    Remove-Module -Name 'GitHub-RepoWatch' -Force -ErrorAction SilentlyContinue
}
