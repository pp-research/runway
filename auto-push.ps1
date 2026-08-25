# auto-push.ps1
# Watches this repo for saved changes to *.html, then commits and pushes.
#
# Scoped two ways on purpose:
#   - only *.html is ever staged, so nothing else in the folder can be
#     published by accident
#   - only commits while the branch below is checked out, so work on any
#     other branch is never touched
#
# The branch is 'main' because GitHub Pages builds this repo from main: a
# save has to land there to reach https://pp-research.github.io/tools/.
# It used to be 'autosave', which is why nothing saved between 19 and 24 Aug
# ever went live. Changing this line without moving the Pages source in the
# repo settings puts the site back to sleep.
#
# Every save is therefore public within about a minute. Work that is not
# ready to be seen belongs on another branch, where this watcher stands down.
#
# Launched from a Startup shortcut, GitAutoPush-tools.lnk; logs to
# .auto-push.log.

$repo     = $PSScriptRoot   # the repo is wherever this script lives
$branch   = 'main'
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
