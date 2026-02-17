function Invoke-RepoWatch {
    <#
    .SYNOPSIS
        Main orchestrator: checks GitHub repos and PSGallery, builds digest, sends email.
    .DESCRIPTION
        Calls Get-RepoActivity to check all repositories for new issues, comments,
        PRs, star and fork changes. Optionally calls Get-PSGalleryStats for download
        tracking. Generates an HTML digest report and optionally sends it via email.
        Updates the state file for delta tracking between runs.
    .PARAMETER Owner
        GitHub username or organization name.
    .PARAMETER Token
        GitHub personal access token. Falls back to $env:GITHUB_TOKEN.
    .PARAMETER SmtpServer
        SMTP server hostname. Required when -SendEmail is specified.
    .PARAMETER EmailTo
        Recipient email address(es). Required when -SendEmail is specified.
    .PARAMETER EmailFrom
        Sender email address. Required when -SendEmail is specified.
    .PARAMETER Port
        SMTP port. Default 587.
    .PARAMETER UseSsl
        Use SSL/TLS for the SMTP connection.
    .PARAMETER SmtpCredential
        PSCredential for SMTP authentication.
    .PARAMETER SinceHours
        Number of hours to look back for activity. Default 24. Range 1-720.
    .PARAMETER StatePath
        Path to the state JSON file. Default: $env:USERPROFILE\.repowatch\state.json
    .PARAMETER SendEmail
        Send the digest via email.
    .PARAMETER OutputPath
        Save the HTML report to a local file.
    .PARAMETER IncludePSGallery
        Include PowerShell Gallery download stats in the digest.
    .PARAMETER PSGalleryAuthor
        Author name to search on PSGallery. Defaults to Owner.
    .PARAMETER RepoFilter
        Specific repository names to check.
    .PARAMETER ExcludeRepos
        Repository names to skip.
    .PARAMETER IncludeForks
        Include forked repositories.
    .PARAMETER SkipIfEmpty
        Do not send email if there is no activity to report.
    .EXAMPLE
        Invoke-RepoWatch -Owner "larro1991" -SendEmail -SmtpServer "smtp.gmail.com" -EmailTo "me@example.com" -EmailFrom "me@example.com" -IncludePSGallery
    .EXAMPLE
        Invoke-RepoWatch -Owner "larro1991" -OutputPath "C:\Reports\digest.html"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter()]
        [string]$Token,

        [Parameter()]
        [string]$SmtpServer,

        [Parameter()]
        [string[]]$EmailTo,

        [Parameter()]
        [string]$EmailFrom,

        [Parameter()]
        [int]$Port = 587,

        [Parameter()]
        [switch]$UseSsl,

        [Parameter()]
        [System.Management.Automation.PSCredential]$SmtpCredential,

        [Parameter()]
        [ValidateRange(1, 720)]
        [int]$SinceHours = 24,

        [Parameter()]
        [string]$StatePath = (Join-Path $env:USERPROFILE '.repowatch\state.json'),

        [Parameter()]
        [switch]$SendEmail,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$IncludePSGallery,

        [Parameter()]
        [string]$PSGalleryAuthor,

        [Parameter()]
        [string[]]$RepoFilter,

        [Parameter()]
        [string[]]$ExcludeRepos,

        [Parameter()]
        [switch]$IncludeForks,

        [Parameter()]
        [switch]$SkipIfEmpty
    )

    # Validate email parameters when SendEmail is specified
    if ($SendEmail) {
        if (-not $SmtpServer) { Write-Error '-SmtpServer is required when -SendEmail is specified.'; return }
        if (-not $EmailTo) { Write-Error '-EmailTo is required when -SendEmail is specified.'; return }
        if (-not $EmailFrom) { Write-Error '-EmailFrom is required when -SendEmail is specified.'; return }
    }

    Write-Host "RepoWatch: Checking activity for '$Owner' (last $SinceHours hours)..." -ForegroundColor Cyan

    # ----- Step 1: Get repository activity -----
    $activityParams = @{
        Owner      = $Owner
        SinceHours = $SinceHours
        StatePath  = $StatePath
    }
    if ($Token) { $activityParams['Token'] = $Token }
    if ($RepoFilter) { $activityParams['RepoFilter'] = $RepoFilter }
    if ($ExcludeRepos) { $activityParams['ExcludeRepos'] = $ExcludeRepos }
    if ($IncludeForks) { $activityParams['IncludeForks'] = $true }

    $activity = Get-RepoActivity @activityParams

    # ----- Step 2: Optionally get PSGallery stats -----
    $galleryStats = $null
    if ($IncludePSGallery) {
        $galleryAuthor = if ($PSGalleryAuthor) { $PSGalleryAuthor } else { $Owner }
        Write-Host "RepoWatch: Checking PowerShell Gallery for '$galleryAuthor'..." -ForegroundColor Cyan
        $galleryStats = Get-PSGalleryStats -Author $galleryAuthor -StatePath $StatePath
    }

    # ----- Step 3: Calculate summary -----
    $activeRepos = @($activity | Where-Object { $_.HasActivity })
    $totalNewIssues = 0
    $totalNewComments = 0
    $totalNewPRs = 0
    foreach ($repo in $activeRepos) {
        if ($repo.NewIssues) { $totalNewIssues += @($repo.NewIssues).Count }
        if ($repo.NewComments) { $totalNewComments += @($repo.NewComments).Count }
        if ($repo.NewPRs) { $totalNewPRs += @($repo.NewPRs).Count }
    }

    $totalDownloads = 0
    if ($galleryStats) {
        foreach ($mod in $galleryStats) { $totalDownloads += $mod.DownloadChange }
    }

    # Console summary
    $summaryParts = @("$($activeRepos.Count) repos with activity")
    if ($totalNewIssues -gt 0) { $summaryParts += "$totalNewIssues new issue$(if ($totalNewIssues -ne 1){'s'})" }
    if ($totalNewComments -gt 0) { $summaryParts += "$totalNewComments new comment$(if ($totalNewComments -ne 1){'s'})" }
    if ($totalNewPRs -gt 0) { $summaryParts += "$totalNewPRs new PR$(if ($totalNewPRs -ne 1){'s'})" }
    if ($totalDownloads -gt 0) { $summaryParts += "$totalDownloads new PSGallery download$(if ($totalDownloads -ne 1){'s'})" }

    Write-Host "RepoWatch: $($summaryParts -join ', ')" -ForegroundColor Green

    # ----- Step 4: Generate HTML digest -----
    $htmlContent = New-HtmlDigest -Activity $activity -PSGalleryStats $galleryStats

    # ----- Step 5: Save HTML report locally if OutputPath specified -----
    if ($OutputPath) {
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllText(
            $OutputPath,
            $htmlContent,
            [System.Text.UTF8Encoding]::new($true)
        )
        Write-Host "RepoWatch: HTML report saved to $OutputPath" -ForegroundColor Cyan
    }

    # ----- Step 6: Send email if requested -----
    $emailResult = $null
    if ($SendEmail) {
        $emailParams = @{
            Activity    = $activity
            SmtpServer  = $SmtpServer
            EmailTo     = $EmailTo
            EmailFrom   = $EmailFrom
            Port        = $Port
        }
        if ($galleryStats) { $emailParams['PSGalleryStats'] = $galleryStats }
        if ($UseSsl) { $emailParams['UseSsl'] = $true }
        if ($SmtpCredential) { $emailParams['Credential'] = $SmtpCredential }
        if ($SkipIfEmpty) { $emailParams['SkipIfEmpty'] = $true }

        $emailResult = Send-ActivityDigest @emailParams

        if ($emailResult.Status -eq 'Sent') {
            Write-Host "RepoWatch: Digest email sent to $($EmailTo -join ', ')" -ForegroundColor Green
        }
        elseif ($emailResult.Status -eq 'Skipped') {
            Write-Host 'RepoWatch: No activity - email skipped.' -ForegroundColor Yellow
        }
        else {
            Write-Host "RepoWatch: Email send failed - $($emailResult.Reason)" -ForegroundColor Red
        }
    }

    # ----- Step 7: Update state file -----
    $reposState = @{}
    foreach ($repo in $activity) {
        $reposState[$repo.RepoName] = @{
            stars = $repo.Stars
            forks = $repo.Forks
        }
    }

    $galleryState = @{}
    if ($galleryStats) {
        foreach ($mod in $galleryStats) {
            $galleryState[$mod.ModuleName] = @{
                downloads = $mod.TotalDownloads
            }
        }
    }

    $stateData = @{
        last_check = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        repos      = $reposState
        psgallery  = $galleryState
    }

    Get-LastCheckTime -StatePath $StatePath -Owner $Owner -Write -Data $stateData
    Write-Verbose "State file updated at: $StatePath"

    # ----- Return summary -----
    return [PSCustomObject]@{
        Owner            = $Owner
        TotalRepos       = @($activity).Count
        ActiveRepos      = $activeRepos.Count
        NewIssues        = $totalNewIssues
        NewComments      = $totalNewComments
        NewPRs           = $totalNewPRs
        PSGalleryModules = if ($galleryStats) { @($galleryStats).Count } else { 0 }
        NewDownloads     = $totalDownloads
        EmailStatus      = if ($emailResult) { $emailResult.Status } else { 'NotRequested' }
        HtmlReportPath   = $OutputPath
        Activity         = $activity
        PSGalleryStats   = $galleryStats
    }
}
