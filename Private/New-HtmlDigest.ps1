function New-HtmlDigest {
    <#
    .SYNOPSIS
        Generates an HTML email body for the RepoWatch activity digest.
    .DESCRIPTION
        Builds a clean, email-friendly HTML document using inline CSS only.
        Renders properly in Outlook, Gmail, and Apple Mail. Shows repo activity,
        new issues, comments, PRs, star/fork changes, and PSGallery download stats.
    .PARAMETER Activity
        Array of RepoActivity objects from Get-RepoActivity.
    .PARAMETER PSGalleryStats
        Array of PSGalleryStats objects from Get-PSGalleryStats.
    .PARAMETER DigestDate
        Date string for the digest header. Defaults to current date.
    .EXAMPLE
        $html = New-HtmlDigest -Activity $activity -PSGalleryStats $stats
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Activity,

        [Parameter()]
        [object[]]$PSGalleryStats,

        [Parameter()]
        [string]$DigestDate = (Get-Date -Format 'yyyy-MM-dd')
    )

    $activeRepos = @()
    if ($Activity) {
        $activeRepos = @($Activity | Where-Object { $_.HasActivity })
    }

    # Calculate summary counts
    $totalNewIssues = 0
    $totalNewComments = 0
    $totalNewPRs = 0
    $totalStarsChange = 0

    foreach ($repo in $activeRepos) {
        if ($repo.NewIssues) { $totalNewIssues += @($repo.NewIssues).Count }
        if ($repo.NewComments) { $totalNewComments += @($repo.NewComments).Count }
        if ($repo.NewPRs) { $totalNewPRs += @($repo.NewPRs).Count }
        $totalStarsChange += $repo.StarsChange
    }

    $totalDownloadChange = 0
    if ($PSGalleryStats) {
        foreach ($mod in $PSGalleryStats) {
            $totalDownloadChange += $mod.DownloadChange
        }
    }

    # Build summary line
    $summaryParts = [System.Collections.Generic.List[string]]::new()
    if ($Activity) {
        $summaryParts.Add("$($activeRepos.Count) repo$(if ($activeRepos.Count -ne 1) {'s'}) with activity")
    }
    if ($totalNewIssues -gt 0) { $summaryParts.Add("$totalNewIssues new issue$(if ($totalNewIssues -ne 1) {'s'})") }
    if ($totalNewComments -gt 0) { $summaryParts.Add("$totalNewComments new comment$(if ($totalNewComments -ne 1) {'s'})") }
    if ($totalNewPRs -gt 0) { $summaryParts.Add("$totalNewPRs new PR$(if ($totalNewPRs -ne 1) {'s'})") }
    if ($totalStarsChange -gt 0) { $summaryParts.Add("+$totalStarsChange star$(if ($totalStarsChange -ne 1) {'s'})") }
    if ($totalDownloadChange -gt 0) { $summaryParts.Add("$totalDownloadChange new download$(if ($totalDownloadChange -ne 1) {'s'})") }

    $summaryLine = if ($summaryParts.Count -gt 0) { $summaryParts -join ' | ' } else { 'No new activity detected.' }

    # Helper: format delta with color
    function Format-Delta {
        param([int]$Value, [switch]$Invert)
        if ($Value -gt 0) {
            $color = if ($Invert) { '#c0392b' } else { '#27ae60' }
            return "<span style=`"color:$color;font-weight:bold;`">+$Value</span>"
        }
        elseif ($Value -lt 0) {
            $color = if ($Invert) { '#27ae60' } else { '#c0392b' }
            return "<span style=`"color:$color;font-weight:bold;`">$Value</span>"
        }
        return '<span style="color:#999;">0</span>'
    }

    # Helper: HTML-encode text
    function Encode-Html {
        param([string]$Text)
        if (-not $Text) { return '' }
        return [System.Net.WebUtility]::HtmlEncode($Text)
    }

    # Start building HTML
    $html = [System.Text.StringBuilder]::new()
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html lang="en">')
    [void]$html.AppendLine('<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>')
    [void]$html.AppendLine('<body style="margin:0;padding:0;background-color:#f5f5f5;font-family:Segoe UI,Helvetica,Arial,sans-serif;font-size:14px;color:#333;">')

    # Container
    [void]$html.AppendLine('<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#f5f5f5;"><tr><td align="center" style="padding:20px 10px;">')
    [void]$html.AppendLine('<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="640" style="background-color:#ffffff;border:1px solid #e0e0e0;border-radius:4px;">')

    # Header
    [void]$html.AppendLine('<tr><td style="background-color:#24292e;color:#ffffff;padding:20px 30px;border-radius:4px 4px 0 0;">')
    [void]$html.AppendLine("<h1 style=`"margin:0;font-size:22px;font-weight:600;`">GitHub RepoWatch Digest</h1>")
    [void]$html.AppendLine("<p style=`"margin:5px 0 0 0;font-size:13px;color:#8b949e;`">$DigestDate</p>")
    [void]$html.AppendLine('</td></tr>')

    # Summary bar
    [void]$html.AppendLine('<tr><td style="background-color:#f0f3f6;padding:12px 30px;border-bottom:1px solid #e0e0e0;">')
    [void]$html.AppendLine("<p style=`"margin:0;font-size:13px;color:#57606a;`">$summaryLine</p>")
    [void]$html.AppendLine('</td></tr>')

    # Repo activity sections
    if ($activeRepos.Count -gt 0) {
        foreach ($repo in $activeRepos) {
            $repoNameEncoded = Encode-Html $repo.RepoName
            $starsHtml = "$(Encode-Html $repo.Stars) stars"
            if ($repo.StarsChange -ne 0) { $starsHtml += " ($(Format-Delta $repo.StarsChange))" }
            $forksHtml = "$(Encode-Html $repo.Forks) forks"
            if ($repo.ForksChange -ne 0) { $forksHtml += " ($(Format-Delta $repo.ForksChange))" }

            [void]$html.AppendLine('<tr><td style="padding:20px 30px;border-bottom:1px solid #e8e8e8;">')
            [void]$html.AppendLine("<h2 style=`"margin:0 0 6px 0;font-size:18px;`"><a href=`"$(Encode-Html $repo.RepoUrl)`" style=`"color:#0969da;text-decoration:none;`">$repoNameEncoded</a></h2>")
            [void]$html.AppendLine("<p style=`"margin:0 0 12px 0;font-size:12px;color:#57606a;`">$starsHtml &nbsp;&middot;&nbsp; $forksHtml</p>")

            # New Issues
            if ($repo.NewIssues -and @($repo.NewIssues).Count -gt 0) {
                [void]$html.AppendLine("<h3 style=`"margin:0 0 8px 0;font-size:14px;color:#c0392b;`">New Issues ($(@($repo.NewIssues).Count))</h3>")
                [void]$html.AppendLine('<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">')
                [void]$html.AppendLine('<tr style="background-color:#f6f8fa;"><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">#</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Title</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Author</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Date</td></tr>')
                foreach ($issue in $repo.NewIssues) {
                    $issueDate = if ($issue.created_at) { ([datetime]$issue.created_at).ToString('MMM dd HH:mm') } else { '' }
                    [void]$html.AppendLine("<tr><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`">#$(Encode-Html ([string]$issue.number))</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`"><a href=`"$(Encode-Html $issue.url)`" style=`"color:#0969da;text-decoration:none;`">$(Encode-Html $issue.title)</a></td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;`">$(Encode-Html $issue.user)</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;white-space:nowrap;`">$issueDate</td></tr>")
                }
                [void]$html.AppendLine('</table>')
            }

            # New Comments
            if ($repo.NewComments -and @($repo.NewComments).Count -gt 0) {
                [void]$html.AppendLine("<h3 style=`"margin:0 0 8px 0;font-size:14px;color:#57606a;`">New Comments ($(@($repo.NewComments).Count))</h3>")
                [void]$html.AppendLine('<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">')
                [void]$html.AppendLine('<tr style="background-color:#f6f8fa;"><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Issue</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">By</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Comment</td></tr>')
                foreach ($comment in $repo.NewComments) {
                    $preview = Encode-Html $comment.body_preview
                    [void]$html.AppendLine("<tr><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;white-space:nowrap;`"><a href=`"$(Encode-Html $comment.url)`" style=`"color:#0969da;text-decoration:none;`">#$(Encode-Html ([string]$comment.issue_number))</a></td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;white-space:nowrap;`">$(Encode-Html $comment.user)</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`">$preview</td></tr>")
                }
                [void]$html.AppendLine('</table>')
            }

            # New PRs
            if ($repo.NewPRs -and @($repo.NewPRs).Count -gt 0) {
                [void]$html.AppendLine("<h3 style=`"margin:0 0 8px 0;font-size:14px;color:#2e7d32;`">New Pull Requests ($(@($repo.NewPRs).Count))</h3>")
                [void]$html.AppendLine('<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">')
                [void]$html.AppendLine('<tr style="background-color:#f6f8fa;"><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">#</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Title</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Author</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Date</td></tr>')
                foreach ($pr in $repo.NewPRs) {
                    $prDate = if ($pr.created_at) { ([datetime]$pr.created_at).ToString('MMM dd HH:mm') } else { '' }
                    [void]$html.AppendLine("<tr><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`">#$(Encode-Html ([string]$pr.number))</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`"><a href=`"$(Encode-Html $pr.url)`" style=`"color:#0969da;text-decoration:none;`">$(Encode-Html $pr.title)</a></td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;`">$(Encode-Html $pr.user)</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;white-space:nowrap;`">$prDate</td></tr>")
                }
                [void]$html.AppendLine('</table>')
            }

            # Updated Issues (not new)
            if ($repo.UpdatedIssues -and @($repo.UpdatedIssues).Count -gt 0) {
                [void]$html.AppendLine("<h3 style=`"margin:0 0 8px 0;font-size:14px;color:#8a6d3b;`">Updated Issues ($(@($repo.UpdatedIssues).Count))</h3>")
                [void]$html.AppendLine('<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">')
                [void]$html.AppendLine('<tr style="background-color:#f6f8fa;"><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">#</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Title</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Author</td></tr>')
                foreach ($upd in $repo.UpdatedIssues) {
                    [void]$html.AppendLine("<tr><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`">#$(Encode-Html ([string]$upd.number))</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`"><a href=`"$(Encode-Html $upd.url)`" style=`"color:#0969da;text-decoration:none;`">$(Encode-Html $upd.title)</a></td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;`">$(Encode-Html $upd.user)</td></tr>")
                }
                [void]$html.AppendLine('</table>')
            }

            [void]$html.AppendLine('</td></tr>')
        }
    }
    elseif (-not $PSGalleryStats -or @($PSGalleryStats).Count -eq 0) {
        [void]$html.AppendLine('<tr><td style="padding:30px;text-align:center;color:#57606a;">')
        [void]$html.AppendLine('<p style="margin:0;font-size:14px;">No new activity detected across your repositories.</p>')
        [void]$html.AppendLine('</td></tr>')
    }

    # PSGallery section
    if ($PSGalleryStats -and @($PSGalleryStats).Count -gt 0) {
        [void]$html.AppendLine('<tr><td style="padding:20px 30px;border-bottom:1px solid #e8e8e8;">')
        [void]$html.AppendLine("<h2 style=`"margin:0 0 12px 0;font-size:18px;color:#5c2d91;`">PowerShell Gallery</h2>")
        [void]$html.AppendLine('<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:4px;">')
        [void]$html.AppendLine('<tr style="background-color:#f6f8fa;"><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Module</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;">Version</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;text-align:right;">Downloads</td><td style="padding:6px 10px;font-size:12px;font-weight:600;color:#57606a;border-bottom:1px solid #e0e0e0;text-align:right;">Change</td></tr>')
        foreach ($mod in $PSGalleryStats) {
            $changeHtml = Format-Delta $mod.DownloadChange
            $galleryUrl = if ($mod.GalleryUrl) { $mod.GalleryUrl } else { "https://www.powershellgallery.com/packages/$($mod.ModuleName)" }
            [void]$html.AppendLine("<tr><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;`"><a href=`"$(Encode-Html $galleryUrl)`" style=`"color:#0969da;text-decoration:none;`">$(Encode-Html $mod.ModuleName)</a></td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;color:#57606a;`">$(Encode-Html $mod.Version)</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;text-align:right;`">$($mod.TotalDownloads.ToString('N0'))</td><td style=`"padding:6px 10px;font-size:13px;border-bottom:1px solid #f0f0f0;text-align:right;`">$changeHtml</td></tr>")
        }
        [void]$html.AppendLine('</table>')
        [void]$html.AppendLine('</td></tr>')
    }

    # Footer
    [void]$html.AppendLine('<tr><td style="padding:16px 30px;background-color:#f6f8fa;border-radius:0 0 4px 4px;border-top:1px solid #e0e0e0;">')
    [void]$html.AppendLine('<p style="margin:0;font-size:11px;color:#8b949e;text-align:center;">Generated by <a href="https://github.com/larro1991/GitHub-RepoWatch" style="color:#0969da;text-decoration:none;">GitHub-RepoWatch</a></p>')
    [void]$html.AppendLine('</td></tr>')

    # Close container
    [void]$html.AppendLine('</table></td></tr></table>')
    [void]$html.AppendLine('</body></html>')

    return $html.ToString()
}
