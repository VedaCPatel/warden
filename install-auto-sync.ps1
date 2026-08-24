# Registers auto-sync.ps1 as a scheduled task that starts at logon and stays
# running. Run this ONCE, in a normal (non-admin) PowerShell window:
#
#   powershell -ExecutionPolicy Bypass -File "$HOME\Desktop\Warden\install-auto-sync.ps1"
#
# To undo:  Unregister-ScheduledTask -TaskName 'Warden Auto Sync' -Confirm:$false

$ErrorActionPreference = 'Stop'

$Repo     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Script   = Join-Path $Repo 'auto-sync.ps1'
$TaskName = 'Warden Auto Sync'

if (-not (Test-Path $Script)) { throw "auto-sync.ps1 not found next to this installer ($Script)" }

# -WindowStyle Hidden so it isn't a console window sitting on the taskbar all day.
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`"" `
  -WorkingDirectory $Repo

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# StartWhenAvailable so a missed logon still starts it; no execution time limit
# because this is a watcher meant to run all day, and the default 3 days would
# silently kill it.
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Description 'Commits and pushes Warden changes to GitHub automatically.' `
  -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host "Installed and started: $TaskName" -ForegroundColor Green
Write-Host "  watching : $Repo"
Write-Host "  log      : $Repo\.git\auto-sync.log"
Write-Host ''
Write-Host 'Edit any file in the Warden folder, save, and it pushes within ~15s.'
Write-Host "Stop it with:  Stop-ScheduledTask -TaskName '$TaskName'"
