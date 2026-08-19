# auto-push.ps1
# Watches this repo for saved changes to *.html, then commits and pushes.
#
# Scoped two ways on purpose:
#   - only *.html is ever staged, so nothing else in the folder can be
#     published by accident
#   - only commits while the 'autosave' branch is checked out, so deliberate
#     work on main is never touched
#
# Runs as a Scheduled Task at logon; writes to .auto-push.log.

$repo     = $PSScriptRoot   # the repo is wherever this script lives
$branch   = 'autosave'
$log      = Join-Path $repo '.auto-push.log'
$interval = 10   # seconds between checks
$settle   = 2    # seconds to let an editor finish writing before committing

function Write-Log($message) {
    $stamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
    "$stamp  $message" | Add-Content -Path $log -Encoding utf8
}

Set-Location $repo
Write-Log "watcher started (branch '$branch', checking every ${interval}s)"

$wasDormant = $false

while ($true) {
    try {
        $current = (git rev-parse --abbrev-ref HEAD).Trim()

        if ($current -ne $branch) {
            # On another branch - stand down, but say so once rather than every tick.
            if (-not $wasDormant) {
                Write-Log "dormant: on '$current', not '$branch' - no autosaving"
                $wasDormant = $true
            }
        } else {
            if ($wasDormant) {
                Write-Log "resumed: back on '$branch'"
                $wasDormant = $false
            }

            if (git status --porcelain -- '*.html') {
                # A save may still be in flight; wait, then re-read the real state.
                Start-Sleep -Seconds $settle
                $changed = @(git status --porcelain -- '*.html' | ForEach-Object { $_.Substring(3) })

                if ($changed.Count -gt 0) {
                    git add -- '*.html'
                    $stamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
                    git commit -q -m "autosave: $stamp"

                    if ($?) {
                        git push -q origin $branch
                        if ($?) {
                            Write-Log "pushed: $($changed -join ', ')"
                        } else {
                            Write-Log "PUSH FAILED - commit is safe locally, will retry next change"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $interval
}
