function Register-RepoWatchTask {
    <#
    .SYNOPSIS
        Creates a Windows Scheduled Task to run Invoke-RepoWatch on a schedule.
    .DESCRIPTION
        Generates a PowerShell wrapper script and registers a Windows Scheduled Task
        that runs Invoke-RepoWatch at the specified interval (Daily, TwiceDaily, or Hourly).
        The wrapper script is saved to $env:USERPROFILE\.repowatch\Run-RepoWatch.ps1.
    .PARAMETER TaskName
        Name for the scheduled task. Default "GitHub-RepoWatch".
    .PARAMETER Owner
        GitHub username or organization name.
    .PARAMETER Token
        GitHub personal access token. Stored in the wrapper script.
    .PARAMETER SmtpServer
        SMTP server hostname for email delivery.
    .PARAMETER EmailTo
        Recipient email address.
    .PARAMETER EmailFrom
        Sender email address.
    .PARAMETER Schedule
        How often to run. Valid: Daily, TwiceDaily, Hourly. Default Daily.
    .PARAMETER Time
        Time to run for Daily schedule (HH:mm format). Default "08:00".
    .PARAMETER RunAs
        Windows account to run the task as. Default is the current user.
    .PARAMETER SinceHours
        Hours to look back for activity. Automatically set based on Schedule if not specified.
    .PARAMETER IncludePSGallery
        Include PSGallery stats in the digest.
    .PARAMETER PSGalleryAuthor
        Author name for PSGallery searches.
    .PARAMETER SkipIfEmpty
        Do not send email when there is no activity.
    .EXAMPLE
        Register-RepoWatchTask -Owner "larro1991" -SmtpServer "smtp.gmail.com" -EmailTo "me@example.com" -EmailFrom "me@example.com"
    .EXAMPLE
        Register-RepoWatchTask -Owner "larro1991" -Schedule Hourly -SkipIfEmpty
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$TaskName = 'GitHub-RepoWatch',

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter()]
        [string]$Token,

        [Parameter()]
        [string]$SmtpServer,

        [Parameter()]
        [string]$EmailTo,

        [Parameter()]
        [string]$EmailFrom,

        [Parameter()]
        [ValidateSet('Daily', 'TwiceDaily', 'Hourly')]
        [string]$Schedule = 'Daily',

        [Parameter()]
        [ValidatePattern('^\d{1,2}:\d{2}$')]
        [string]$Time = '08:00',

        [Parameter()]
        [string]$RunAs = "$env:USERDOMAIN\$env:USERNAME",

        [Parameter()]
        [int]$SinceHours,

        [Parameter()]
        [switch]$IncludePSGallery,

        [Parameter()]
        [string]$PSGalleryAuthor,

        [Parameter()]
        [switch]$SkipIfEmpty
    )

    # Determine SinceHours default based on schedule
    if (-not $SinceHours) {
        $SinceHours = switch ($Schedule) {
            'Daily'      { 25 }    # 25h to catch overlap
            'TwiceDaily' { 13 }    # 13h for twice daily
            'Hourly'     { 2  }    # 2h for hourly
        }
    }

    # Build wrapper script
    $wrapperDir = Join-Path $env:USERPROFILE '.repowatch'
    if (-not (Test-Path -Path $wrapperDir)) {
        New-Item -Path $wrapperDir -ItemType Directory -Force | Out-Null
    }
    $wrapperPath = Join-Path $wrapperDir 'Run-RepoWatch.ps1'

    # Find module path
    $modulePath = $PSScriptRoot
    if ($modulePath -and $modulePath.EndsWith('Public')) {
        $modulePath = Split-Path -Path $modulePath -Parent
    }
    if (-not $modulePath) {
        $modulePath = (Get-Module -Name GitHub-RepoWatch).ModuleBase
    }

    # Build the Invoke-RepoWatch command string
    $invokeParams = [System.Collections.Generic.List[string]]::new()
    $invokeParams.Add("-Owner '$Owner'")
    $invokeParams.Add("-SinceHours $SinceHours")

    if ($SmtpServer -and $EmailTo -and $EmailFrom) {
        $invokeParams.Add('-SendEmail')
        $invokeParams.Add("-SmtpServer '$SmtpServer'")
        $invokeParams.Add("-EmailTo '$EmailTo'")
        $invokeParams.Add("-EmailFrom '$EmailFrom'")
    }

    if ($IncludePSGallery) { $invokeParams.Add('-IncludePSGallery') }
    if ($PSGalleryAuthor) { $invokeParams.Add("-PSGalleryAuthor '$PSGalleryAuthor'") }
    if ($SkipIfEmpty) { $invokeParams.Add('-SkipIfEmpty') }

    $invokeCmd = "Invoke-RepoWatch $($invokeParams -join ' ')"

    $wrapperScript = @"
# GitHub-RepoWatch Scheduled Task Wrapper
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Schedule: $Schedule

`$ErrorActionPreference = 'Stop'

# Set GitHub token if provided
$(if ($Token) { "`$env:GITHUB_TOKEN = '$Token'" } else { '# No GitHub token configured — using unauthenticated access (60 req/hr limit)' })

# Import the module
try {
    Import-Module '$modulePath' -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to import GitHub-RepoWatch module: `$_"
    exit 1
}

# Run RepoWatch
try {
    $invokeCmd
}
catch {
    Write-Error "RepoWatch execution failed: `$_"
    exit 1
}
"@

    # Write wrapper script with UTF-8 BOM
    [System.IO.File]::WriteAllText(
        $wrapperPath,
        $wrapperScript,
        [System.Text.UTF8Encoding]::new($true)
    )
    Write-Verbose "Wrapper script created: $wrapperPath"

    # Build scheduled task trigger
    $trigger = switch ($Schedule) {
        'Daily' {
            New-ScheduledTaskTrigger -Daily -At $Time
        }
        'TwiceDaily' {
            @(
                (New-ScheduledTaskTrigger -Daily -At $Time),
                (New-ScheduledTaskTrigger -Daily -At (
                    [datetime]::ParseExact($Time, 'HH:mm', $null).AddHours(12).ToString('HH:mm')
                ))
            )
        }
        'Hourly' {
            $t = New-ScheduledTaskTrigger -Once -At $Time -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)
            $t
        }
    }

    # Build task action
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$wrapperPath`""

    # Task settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -MultipleInstances IgnoreNew

    # Register the task
    if ($PSCmdlet.ShouldProcess($TaskName, 'Register Scheduled Task')) {
        try {
            # Remove existing task if present
            $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
                Write-Verbose "Removed existing task: $TaskName"
            }

            $taskParams = @{
                TaskName    = $TaskName
                Action      = $action
                Trigger     = $trigger
                Settings    = $settings
                Description = "GitHub RepoWatch: Monitors repos for $Owner and sends activity digests."
                Force       = $true
            }

            $task = Register-ScheduledTask @taskParams
            Write-Host "Scheduled task '$TaskName' registered successfully." -ForegroundColor Green
            Write-Host "  Schedule : $Schedule" -ForegroundColor Cyan
            Write-Host "  Time     : $Time" -ForegroundColor Cyan
            Write-Host "  Wrapper  : $wrapperPath" -ForegroundColor Cyan

            # Show next run time
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($taskInfo -and $taskInfo.NextRunTime) {
                Write-Host "  Next Run : $($taskInfo.NextRunTime)" -ForegroundColor Green
            }

            return $task
        }
        catch {
            Write-Error "Failed to register scheduled task: $_"
        }
    }
}
