function Send-ActivityDigest {
    <#
    .SYNOPSIS
        Sends an HTML email digest of all GitHub and PSGallery activity.
    .DESCRIPTION
        Accepts activity data from Get-RepoActivity and stats from Get-PSGalleryStats,
        generates an HTML email using New-HtmlDigest, and sends it via SMTP using
        Send-MailMessage. Supports the -SkipIfEmpty switch to suppress emails when
        there is no new activity.
    .PARAMETER Activity
        Array of RepoActivity objects from Get-RepoActivity. Accepts pipeline input.
    .PARAMETER PSGalleryStats
        Array of PSGalleryStats objects from Get-PSGalleryStats.
    .PARAMETER SmtpServer
        SMTP server hostname (e.g., "smtp.gmail.com").
    .PARAMETER EmailTo
        Recipient email address(es).
    .PARAMETER EmailFrom
        Sender email address.
    .PARAMETER Port
        SMTP port. Default 587.
    .PARAMETER UseSsl
        Use SSL/TLS for the SMTP connection. Default true.
    .PARAMETER Credential
        PSCredential for SMTP authentication.
    .PARAMETER Subject
        Email subject line. Default "GitHub RepoWatch Digest - {date}".
    .PARAMETER SkipIfEmpty
        Do not send the email if there is no activity to report.
    .EXAMPLE
        $activity | Send-ActivityDigest -SmtpServer "smtp.gmail.com" -EmailTo "me@example.com" -EmailFrom "me@example.com" -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object[]]$Activity,

        [Parameter()]
        [object[]]$PSGalleryStats,

        [Parameter(Mandatory)]
        [string]$SmtpServer,

        [Parameter(Mandatory)]
        [string[]]$EmailTo,

        [Parameter(Mandatory)]
        [string]$EmailFrom,

        [Parameter()]
        [int]$Port = 587,

        [Parameter()]
        [switch]$UseSsl = $true,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [string]$Subject,

        [Parameter()]
        [switch]$SkipIfEmpty
    )

    begin {
        $allActivity = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($Activity) {
            foreach ($item in $Activity) {
                $allActivity.Add($item)
            }
        }
    }

    end {
        # Determine if there is any activity at all
        $hasAnyActivity = $false

        if ($allActivity.Count -gt 0) {
            foreach ($repo in $allActivity) {
                if ($repo.HasActivity) {
                    $hasAnyActivity = $true
                    break
                }
            }
        }

        if (-not $hasAnyActivity -and $PSGalleryStats) {
            foreach ($mod in $PSGalleryStats) {
                if ($mod.HasNewDownloads) {
                    $hasAnyActivity = $true
                    break
                }
            }
        }

        # Skip if empty and flag is set
        if ($SkipIfEmpty -and -not $hasAnyActivity) {
            Write-Verbose 'No activity detected and -SkipIfEmpty is set. Skipping email.'
            return [PSCustomObject]@{
                Status        = 'Skipped'
                Reason        = 'No activity'
                ActivityCount = 0
                SentTo        = $EmailTo
            }
        }

        # Generate HTML body
        $htmlBody = New-HtmlDigest -Activity $allActivity.ToArray() -PSGalleryStats $PSGalleryStats

        # Build subject line
        if (-not $Subject) {
            $Subject = "GitHub RepoWatch Digest - $(Get-Date -Format 'yyyy-MM-dd')"
        }

        # Build Send-MailMessage parameters
        $mailParams = @{
            From       = $EmailFrom
            To         = $EmailTo
            Subject    = $Subject
            Body       = $htmlBody
            BodyAsHtml = $true
            SmtpServer = $SmtpServer
            Port       = $Port
            Encoding   = [System.Text.Encoding]::UTF8
        }

        if ($UseSsl) {
            $mailParams['UseSsl'] = $true
        }

        if ($Credential) {
            $mailParams['Credential'] = $Credential
        }

        try {
            Send-MailMessage @mailParams -ErrorAction Stop
            Write-Verbose "Digest email sent to: $($EmailTo -join ', ')"

            $activeCount = @($allActivity | Where-Object { $_.HasActivity }).Count

            return [PSCustomObject]@{
                Status        = 'Sent'
                Reason        = $null
                ActivityCount = $activeCount
                SentTo        = $EmailTo
            }
        }
        catch {
            Write-Error "Failed to send digest email: $_"
            return [PSCustomObject]@{
                Status        = 'Failed'
                Reason        = $_.Exception.Message
                ActivityCount = 0
                SentTo        = $EmailTo
            }
        }
    }
}
