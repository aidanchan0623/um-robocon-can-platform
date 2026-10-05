param([Parameter(Mandatory=$true)][string]$RunDirectory)
$Host.UI.RawUI.WindowTitle = 'CAN 1 Mbit/s - live bench-test progress'
Write-Host 'CAN 1 Mbit/s: G474 <-> F303 bench test' -ForegroundColor Cyan
Write-Host 'READ-ONLY monitor. This window does not send commands or own the COM port.'
Write-Host 'Close this window whenever you like; it will not interrupt the test.'
Write-Host ''
$log = Join-Path $RunDirectory 'live-progress.txt'
while (-not (Test-Path -LiteralPath $log)) { Start-Sleep -Milliseconds 300 }
Get-Content -LiteralPath $log -Wait
