function Get-GitHubAPI {
    <#
    .SYNOPSIS
        GitHub REST API helper with authentication and pagination support.
    .DESCRIPTION
        Calls the GitHub REST API, handles authentication via personal access token,
        follows pagination via Link headers, and provides rate-limit awareness.
        Works without a token for public repos (60 req/hr vs 5000 req/hr with token).
    .PARAMETER Endpoint
        The API endpoint path (e.g., "/repos/{owner}/{repo}/issues").
    .PARAMETER Token
        GitHub personal access token. Falls back to $env:GITHUB_TOKEN if not provided.
    .PARAMETER Method
        HTTP method. Default is GET.
    .PARAMETER Body
        Hashtable to send as JSON body for POST/PATCH/PUT requests.
    .EXAMPLE
        Get-GitHubAPI -Endpoint "/repos/larro1991/AD-SecurityAudit/issues" -Token $token
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [string]$Token,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [hashtable]$Body
    )

    $baseUrl = 'https://api.github.com'
    $url = if ($Endpoint.StartsWith('http')) { $Endpoint } else { "$baseUrl$Endpoint" }

    # Build headers
    $headers = @{
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'GitHub-RepoWatch-PowerShell'
    }

    # Resolve token: parameter > environment variable
    $resolvedToken = if ($Token) { $Token } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $null }
    if ($resolvedToken) {
        $headers['Authorization'] = "Bearer $resolvedToken"
    }

    $allResults = [System.Collections.Generic.List[object]]::new()
    $currentUrl = $url

    do {
        $nextUrl = $null

        $splat = @{
            Uri                = $currentUrl
            Method             = $Method
            Headers            = $headers
            ContentType        = 'application/json'
            UseBasicParsing    = $true
            ErrorAction        = 'Stop'
            ResponseHeadersVariable = 'responseHeaders'
        }

        if ($Body -and $Method -ne 'GET') {
            $splat['Body'] = ($Body | ConvertTo-Json -Depth 10)
        }

        try {
            $response = Invoke-RestMethod @splat

            # Check rate limit from response headers
            if ($responseHeaders -and $responseHeaders['X-RateLimit-Remaining']) {
                $remaining = [int]$responseHeaders['X-RateLimit-Remaining'][0]
                if ($remaining -le 5) {
                    $resetEpoch = [int]$responseHeaders['X-RateLimit-Reset'][0]
                    $resetTime = [System.DateTimeOffset]::FromUnixTimeSeconds($resetEpoch).LocalDateTime
                    $waitSeconds = [math]::Max(1, ($resetTime - (Get-Date)).TotalSeconds)
                    Write-Warning "GitHub API rate limit nearly exhausted ($remaining remaining). Waiting $([math]::Ceiling($waitSeconds)) seconds until reset."
                    Start-Sleep -Seconds ([math]::Ceiling($waitSeconds) + 1)
                }
            }

            # Collect results
            if ($response -is [array]) {
                foreach ($item in $response) {
                    $allResults.Add($item)
                }
            }
            else {
                $allResults.Add($response)
            }

            # Parse Link header for pagination (rel="next")
            if ($responseHeaders -and $responseHeaders['Link']) {
                $linkHeader = $responseHeaders['Link'][0]
                if ($linkHeader -match '<([^>]+)>;\s*rel="next"') {
                    $nextUrl = $Matches[1]
                }
            }

            $currentUrl = $nextUrl
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            switch ($statusCode) {
                401 {
                    Write-Error "GitHub API authentication failed. Check your token. Endpoint: $currentUrl"
                    return
                }
                403 {
                    if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['X-RateLimit-Remaining']) {
                        Write-Error "GitHub API rate limit exceeded. Wait for reset or provide an authenticated token."
                    }
                    else {
                        Write-Error "GitHub API access forbidden for endpoint: $currentUrl"
                    }
                    return
                }
                404 {
                    Write-Verbose "GitHub API returned 404 for endpoint: $currentUrl (resource not found, returning empty)"
                    return @()
                }
                default {
                    Write-Error "GitHub API error calling $currentUrl : $_"
                    return
                }
            }
        }
    } while ($currentUrl)

    # If only one result and it was not an array response, return the single object
    if ($allResults.Count -eq 1 -and $response -isnot [array]) {
        return $allResults[0]
    }

    return $allResults.ToArray()
}
