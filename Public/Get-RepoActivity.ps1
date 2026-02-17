function Get-RepoActivity {
    <#
    .SYNOPSIS
        Checks all repos for a GitHub user/org for new activity since the last check.
    .DESCRIPTION
        Queries the GitHub API for each repository owned by the specified user or
        organization. Returns new issues, comments, pull requests, star changes,
        and fork changes since the specified cutoff time or since the last tracked
        check. Forked repos are excluded by default.
    .PARAMETER Owner
        GitHub username or organization name.
    .PARAMETER Token
        GitHub personal access token. Falls back to $env:GITHUB_TOKEN.
    .PARAMETER SinceHours
        Number of hours to look back for activity. Default 24. Range 1-720.
    .PARAMETER SinceDate
        Explicit cutoff datetime. Overrides SinceHours when specified.
    .PARAMETER RepoFilter
        Specific repository names to check. Default checks all public repos.
    .PARAMETER ExcludeRepos
        Repository names to skip.
    .PARAMETER IncludeForks
        Include forked repositories. By default forks are skipped.
    .PARAMETER StatePath
        Path to the state JSON file for delta tracking.
    .EXAMPLE
        Get-RepoActivity -Owner "larro1991" -SinceHours 48
    .EXAMPLE
        Get-RepoActivity -Owner "larro1991" -RepoFilter "AD-SecurityAudit","ToolBridge-MCP"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter()]
        [string]$Token,

        [Parameter()]
        [ValidateRange(1, 720)]
        [int]$SinceHours = 24,

        [Parameter()]
        [datetime]$SinceDate,

        [Parameter()]
        [string[]]$RepoFilter,

        [Parameter()]
        [string[]]$ExcludeRepos,

        [Parameter()]
        [switch]$IncludeForks,

        [Parameter()]
        [string]$StatePath = (Join-Path $env:USERPROFILE '.repowatch\state.json')
    )

    # Determine the cutoff time
    $sinceTime = if ($SinceDate) {
        $SinceDate.ToUniversalTime()
    }
    else {
        (Get-Date).AddHours(-$SinceHours).ToUniversalTime()
    }
    $sinceIso = $sinceTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Verbose "Checking activity since: $sinceIso"

    # Resolve token
    $resolvedToken = if ($Token) { $Token } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }

    # Load previous state for delta comparison
    $state = Get-LastCheckTime -StatePath $StatePath -Owner $Owner

    # Get repositories list
    if ($RepoFilter -and $RepoFilter.Count -gt 0) {
        # Fetch specific repos
        $repos = foreach ($repoName in $RepoFilter) {
            $repoData = Get-GitHubAPI -Endpoint "/repos/$Owner/$repoName" -Token $resolvedToken
            if ($repoData) { $repoData }
        }
    }
    else {
        # Fetch all repos for the owner (handles pagination)
        $repos = Get-GitHubAPI -Endpoint "/users/$Owner/repos?type=owner&per_page=100&sort=updated" -Token $resolvedToken
    }

    if (-not $repos) {
        Write-Warning "No repositories found for owner '$Owner'."
        return @()
    }

    # Filter repos
    $filteredRepos = @($repos)

    if (-not $IncludeForks) {
        $filteredRepos = @($filteredRepos | Where-Object { -not $_.fork })
    }

    if ($ExcludeRepos -and $ExcludeRepos.Count -gt 0) {
        $filteredRepos = @($filteredRepos | Where-Object { $_.name -notin $ExcludeRepos })
    }

    Write-Verbose "Checking $($filteredRepos.Count) repositories for activity."

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($repo in $filteredRepos) {
        $repoName = $repo.name
        Write-Verbose "Processing repo: $repoName"

        # Current star/fork counts
        $currentStars = [int]$repo.stargazers_count
        $currentForks = [int]$repo.forks_count

        # Get previous counts from state
        $prevStars = 0
        $prevForks = 0
        if ($state.repos -and $state.repos.PSObject.Properties.Name -contains $repoName) {
            $prevData = $state.repos.$repoName
            $prevStars = if ($prevData.PSObject.Properties.Name -contains 'stars') { [int]$prevData.stars } else { $currentStars }
            $prevForks = if ($prevData.PSObject.Properties.Name -contains 'forks') { [int]$prevData.forks } else { $currentForks }
        }
        else {
            # First check for this repo; set previous to current so delta is 0
            $prevStars = $currentStars
            $prevForks = $currentForks
        }

        $starsChange = $currentStars - $prevStars
        $forksChange = $currentForks - $prevForks

        # Fetch new/updated issues (since cutoff)
        $issuesRaw = Get-GitHubAPI -Endpoint "/repos/$Owner/$repoName/issues?state=open&since=$sinceIso&per_page=100" -Token $resolvedToken
        $newIssues = [System.Collections.Generic.List[object]]::new()
        $updatedIssues = [System.Collections.Generic.List[object]]::new()

        if ($issuesRaw) {
            foreach ($issue in @($issuesRaw)) {
                # Skip pull requests (GitHub API returns PRs in issues endpoint)
                if ($issue.pull_request) { continue }

                $issueObj = [PSCustomObject]@{
                    number     = $issue.number
                    title      = $issue.title
                    user       = $issue.user.login
                    created_at = $issue.created_at
                    url        = $issue.html_url
                }

                $createdAt = [datetime]$issue.created_at
                if ($createdAt.ToUniversalTime() -ge $sinceTime) {
                    $newIssues.Add($issueObj)
                }
                else {
                    $updatedIssues.Add($issueObj)
                }
            }
        }

        # Fetch new comments on issues
        $commentsRaw = Get-GitHubAPI -Endpoint "/repos/$Owner/$repoName/issues/comments?since=$sinceIso&per_page=100" -Token $resolvedToken
        $newComments = [System.Collections.Generic.List[object]]::new()

        if ($commentsRaw) {
            foreach ($comment in @($commentsRaw)) {
                # Extract issue number from the issue_url
                $issueNumber = 0
                if ($comment.issue_url -match '/issues/(\d+)$') {
                    $issueNumber = [int]$Matches[1]
                }

                $bodyPreview = if ($comment.body.Length -gt 100) {
                    $comment.body.Substring(0, 100) + '...'
                }
                else {
                    $comment.body
                }
                # Collapse newlines in preview
                $bodyPreview = $bodyPreview -replace '[\r\n]+', ' '

                $newComments.Add([PSCustomObject]@{
                    issue_number = $issueNumber
                    user         = $comment.user.login
                    body_preview = $bodyPreview
                    created_at   = $comment.created_at
                    url          = $comment.html_url
                })
            }
        }

        # Fetch new PRs
        $prsRaw = Get-GitHubAPI -Endpoint "/repos/$Owner/$repoName/pulls?state=open&sort=created&direction=desc&per_page=100" -Token $resolvedToken
        $newPRs = [System.Collections.Generic.List[object]]::new()

        if ($prsRaw) {
            foreach ($pr in @($prsRaw)) {
                $prCreated = [datetime]$pr.created_at
                if ($prCreated.ToUniversalTime() -ge $sinceTime) {
                    $newPRs.Add([PSCustomObject]@{
                        number     = $pr.number
                        title      = $pr.title
                        user       = $pr.user.login
                        created_at = $pr.created_at
                        url        = $pr.html_url
                    })
                }
            }
        }

        # Note: Discussions require GraphQL API (not available via REST).
        # This is acknowledged and skipped for REST-only implementation.

        # Determine if there is any activity
        $hasActivity = (
            $newIssues.Count -gt 0 -or
            $newComments.Count -gt 0 -or
            $newPRs.Count -gt 0 -or
            $updatedIssues.Count -gt 0 -or
            $starsChange -ne 0 -or
            $forksChange -ne 0
        )

        $repoActivity = [PSCustomObject]@{
            RepoName      = $repoName
            RepoUrl       = $repo.html_url
            Stars         = $currentStars
            StarsChange   = $starsChange
            Forks         = $currentForks
            ForksChange   = $forksChange
            NewIssues     = $newIssues.ToArray()
            NewComments   = $newComments.ToArray()
            NewPRs        = $newPRs.ToArray()
            UpdatedIssues = $updatedIssues.ToArray()
            HasActivity   = $hasActivity
        }

        $results.Add($repoActivity)
    }

    return $results.ToArray()
}
