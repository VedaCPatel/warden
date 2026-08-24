# ═════════════════════════════════════════════════════════════════════════════
# auto-sync.ps1 — watches this folder and pushes every change to GitHub.
#
# Run it once (or let the scheduled task run it at logon) and leave it alone.
# Edit any file under ~/Desktop/Warden, save, and within ~15 seconds the change
# is committed and pushed to VedaCPatel/warden.
#
# Why a debounce rather than commit-on-save: editors write files in bursts
# (temp file, rename, sometimes a second write for the sourcemap). Committing on
# the first event would produce three commits for one save and occasionally
# catch a half-written file. So a save schedules a flush, and any further save
# pushes the flush back. The tree only gets committed once it has been quiet.
# ═════════════════════════════════════════════════════════════════════════════

# NOT 'Stop'. git writes ordinary progress to stderr, and under 'Stop' PowerShell
# promotes native-command stderr to a terminating error -- one transient network
# blip would kill the watcher silently and it would look like auto-sync "just
# stopped working". Failures are detected via $LASTEXITCODE instead, explicitly.
$ErrorActionPreference = 'Continue'

$Repo        = Split-Path -Parent $MyInvocation.MyCommand.Definition
$QuietWindow = 15      # seconds of no-changes before committing
$PollEvery   = 3       # seconds between checks
$LogFile     = Join-Path $Repo '.git\auto-sync.log'

function Write-Log($msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  try { Add-Content -Path $LogFile -Value $line -Encoding utf8 } catch {}
}

# Only ever one copy running, or two loops race on the same index.lock.
$mutex = New-Object System.Threading.Mutex($false, 'Global\WardenAutoSync')
if (-not $mutex.WaitOne(0)) {
  Write-Log 'another auto-sync is already running - exiting'
  exit 0
}

Set-Location $Repo
Write-Log "watching $Repo (quiet window ${QuietWindow}s)"

$pendingSince = $null

while ($true) {
  Start-Sleep -Seconds $PollEvery

  # The entire body is guarded: this process is meant to outlive every kind of
  # transient failure (locked file, dropped wifi, a git upgrade mid-run). An
  # unhandled throw here would end the watcher and nothing would say so.
  try {

  # porcelain is empty exactly when the tree is clean, including untracked.
  $dirty = git status --porcelain 2>$null

  if ([string]::IsNullOrWhiteSpace($dirty)) {
    $pendingSince = $null
    continue
  }

  if ($null -eq $pendingSince) {
    $pendingSince = Get-Date
    Write-Log 'change detected - waiting for edits to settle'
    continue
  }

  if (((Get-Date) - $pendingSince).TotalSeconds -lt $QuietWindow) { continue }

  $pendingSince = $null

  # A commit mid-rebase/merge would land on a detached or conflicted state.
  if ((Test-Path '.git\MERGE_HEAD') -or (Test-Path '.git\rebase-merge') -or
      (Test-Path '.git\rebase-apply')) {
    Write-Log 'merge or rebase in progress - skipping this round'
    continue
  }

  $files = ($dirty -split "`n" | Where-Object { $_ }).Count
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

  git add -A 2>&1 | Out-Null

  # add -A can end up staging nothing (e.g. the only change was ignored).
  git diff --cached --quiet 2>$null
  if ($LASTEXITCODE -eq 0) { Write-Log 'nothing staged - skipping'; continue }

  git -c user.name='Veda' -c user.email='vedapatel05@gmail.com' `
      commit -q -m "auto: $stamp ($files file(s))" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Log 'commit failed - will retry'; continue }

  Write-Log "committed $files file(s)"

  # Try a plain push first. Pulling unconditionally would rewrite local history
  # on every single save for no reason; the rebase is only needed when the push
  # is actually rejected as non-fast-forward.
  $out = git push origin main 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Log 'pushed to origin/main'
  } else {
    Write-Log 'push rejected - pulling with rebase and retrying'
    git pull --rebase --autostash origin main 2>&1 | Out-Null

    $out = git push origin main 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Log 'pushed to origin/main after rebase'
    } else {
      # Log the real reason. Swallowing it is what makes a broken sync look
      # like it is working -- the commit is safe locally either way.
      Write-Log "PUSH FAILED - commit saved locally, will retry: $($out -join ' ')"
    }
  }

  } catch {
    Write-Log "unexpected error (watcher continues): $($_.Exception.Message)"
  }
}
