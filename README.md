# GitHub-RepoWatch

Monitor your GitHub repos and PSGallery packages for new issues, comments, PRs, stars, and download stats. Get email digests on a schedule.

## The Problem

You published 20 open-source modules. Someone opened an issue on one of them 3 days ago. You didn't notice because you don't check GitHub every day. That's a bad look for a maintainer.

GitHub-RepoWatch checks all your repos on a schedule and sends you a single email digest with everything that changed. No more missed issues. No more stale PRs. No more "sorry I didn't see this" comments two weeks late.

## What Gets Monitored

| Source | What's Tracked |
|---|---|
| GitHub Issues | New issues opened, issues updated since last check |
| GitHub Comments | New comments on issues (with preview text) |
| GitHub Pull Requests | New PRs opened |
| GitHub Stars | Star count changes per repo |
| GitHub Forks | Fork count changes per repo |
| PSGallery Downloads | Total download count changes per module |

> **Note:** GitHub Discussions require the GraphQL API and are not currently monitored. REST API coverage includes issues, comments, PRs, stars, and forks.

## Quick Start

### One-Time Check (Console Output)

```powershell
Import-Module .\GitHub-RepoWatch

# Check all repos and print summary to console
Invoke-RepoWatch -Owner "larro1991"

# Save HTML report locally
Invoke-RepoWatch -Owner "larro1991" -OutputPath "C:\Reports\digest.html"
```

### One-Time Check with Email

```powershell
Invoke-RepoWatch -Owner "larro1991" `
    -SendEmail `
    -SmtpServer "smtp.gmail.com" `
    -EmailTo "you@email.com" `
    -EmailFrom "you@email.com" `
    -SmtpCredential (Get-Credential) `
    -UseSsl `
    -IncludePSGallery `
    -SkipIfEmpty
```

### Set Up Daily Digest (Scheduled Task)

```powershell
Register-RepoWatchTask -Owner "larro1991" `
    -SmtpServer "smtp.gmail.com" `
    -EmailTo "you@email.com" `
    -EmailFrom "you@email.com" `
    -Token $env:GITHUB_TOKEN `
    -Schedule Daily `
    -Time "08:00" `
    -IncludePSGallery `
    -SkipIfEmpty
```

This creates a Windows Scheduled Task that runs every morning at 8 AM. The wrapper script is saved to `%USERPROFILE%\.repowatch\Run-RepoWatch.ps1`.

## Running Without Email

You don't need email at all. RepoWatch works perfectly as a console tool:

```powershell
# Console summary only
Invoke-RepoWatch -Owner "larro1991"

# Save HTML report to file
Invoke-RepoWatch -Owner "larro1991" -OutputPath "C:\Reports\digest.html" -IncludePSGallery

# Get the full activity objects for scripting
$result = Invoke-RepoWatch -Owner "larro1991"
$result.Activity | Where-Object HasActivity | ForEach-Object {
    Write-Host "$($_.RepoName): $(@($_.NewIssues).Count) new issues"
}
```

## Email Setup

### Gmail (App Password)

1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable 2-Step Verification if not already on
3. Go to App Passwords and generate one for "Mail"
4. Use these settings:
   - SmtpServer: `smtp.gmail.com`
   - Port: `587`
   - UseSsl: `$true`
   - Credential: your Gmail address + the app password

```powershell
$cred = New-Object PSCredential("you@gmail.com", (ConvertTo-SecureString "your-app-password" -AsPlainText -Force))
```

### Outlook / Office 365

- SmtpServer: `smtp.office365.com`
- Port: `587`
- UseSsl: `$true`
- Credential: your O365 credentials

### Generic SMTP

Any SMTP server works. Just provide the server, port, and credentials if required.

## GitHub Token Setup

A GitHub token is optional for public repos but recommended to avoid the 60 requests/hour rate limit (vs. 5,000/hour with a token).

1. Go to [GitHub Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens)
2. Generate a new token (classic) with the `repo` scope (for private repos) or `public_repo` (for public only)
3. Set it as an environment variable or pass it directly:

```powershell
# Environment variable (recommended)
$env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxxxxxxxxxx"

# Or pass directly
Invoke-RepoWatch -Owner "larro1991" -Token "ghp_xxxxxxxxxxxxxxxxxxxx"
```

## State Tracking

RepoWatch stores state between runs in `%USERPROFILE%\.repowatch\state.json`. This file tracks:

- Last check timestamp
- Star and fork counts per repo (for calculating deltas)
- PSGallery download counts per module (for calculating deltas)

On the first run, all deltas are zero since there is no previous baseline.

## Functions

| Function | Description |
|---|---|
| `Invoke-RepoWatch` | Main orchestrator. Checks everything, builds digest, optionally emails. |
| `Get-RepoActivity` | Checks GitHub repos for new issues, comments, PRs, stars, forks. |
| `Get-PSGalleryStats` | Checks PSGallery for download count changes. |
| `Send-ActivityDigest` | Sends the HTML email digest via SMTP. |
| `Register-RepoWatchTask` | Creates a Windows Scheduled Task for automated runs. |

## Requirements

- PowerShell 5.1 or later (Windows PowerShell or PowerShell 7+)
- Internet access to GitHub API and PowerShell Gallery
- (Optional) GitHub personal access token for higher rate limits
- (Optional) SMTP server access for email delivery
- (Optional) Administrator rights for creating scheduled tasks

## Feedback & Contributions

Found a bug? Have a feature idea? Want to improve something?

- **GitHub Issues**: [Open an issue](https://github.com/larro1991/GitHub-RepoWatch/issues) for bugs, feature requests, or questions
- **Pull Requests**: Contributions are welcome — fork, branch, and submit a PR
- **All Projects**: See everything at [larro1991.github.io](https://larro1991.github.io)

## License

MIT License. See [LICENSE](LICENSE) for details.
