param(
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [Parameter(Mandatory=$true)][string]$Programmer,
    [Parameter(Mandatory=$true)][string]$F303Serial,
    [Parameter(Mandatory=$true)][string]$G474Serial,
    [string]$Port = 'COM7',
    [ValidateRange(10,1800)][int]$SoakSeconds = 1800
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath (Join-Path $RunDirectory 'suite.json')) { throw 'Suite already exists.' }
New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null
$progressPath = Join-Path $RunDirectory 'live-progress.txt'
$cancelFile = Join-Path $RunDirectory 'STOP'
$stages = [Collections.Generic.List[object]]::new()
$suite = [ordered]@{
    started=[DateTimeOffset]::Now.ToString('o'); finished=$null; state='RUNNING'; pass=$false;
    current_stage='Preparing'; stages=@(); total_verified_pairs=0; error=$null;
    final_pause=$null;
    limits='Two-node normal-mode bench only. No motor commands, firmware changes, cold power cycles, physical disconnections, temperature or EMI tests.'
}
function Save-Suite {
    $suite.stages = @($stages.ToArray())
    $suite.total_verified_pairs = [long](($stages | ForEach-Object { $_.pairs } | Measure-Object -Sum).Sum)
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'suite.json'),($suite | ConvertTo-Json -Depth 10))
}
function Progress([string]$Message) {
    $line = "$(Get-Date -Format 'HH:mm:ss')  $Message"
    Add-Content -LiteralPath $progressPath -Value $line
    Write-Host $line
}
function Confirm-Pause {
    $check = [IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
    $check.DtrEnable=$false; $check.RtsEnable=$false
    try {
        $check.Open(); $check.DiscardInBuffer(); $check.Write('P')
        $timer = [Diagnostics.Stopwatch]::StartNew(); $textBuffer=''
        while ($timer.Elapsed.TotalSeconds -lt 6) {
            $textBuffer += $check.ReadExisting()
            while ($textBuffer.Contains("`n")) {
                $split = $textBuffer.IndexOf("`n")
                $line = $textBuffer.Substring(0,$split).Trim(); $textBuffer=$textBuffer.Substring($split+1)
                if ($line -match '^CAN1M G474 state=(PAUSED|FAULT) .*pending=(\d+) ') {
                    $status=[ordered]@{confirmed=$true;state=$Matches[1];pending=[int]$Matches[2];timestamp=[DateTimeOffset]::Now.ToString('o')}
                    [IO.File]::WriteAllText((Join-Path $RunDirectory 'final-pause-serial.txt'),$line)
                    return [pscustomobject]$status
                }
            }
            Start-Sleep -Milliseconds 30
        }
        throw 'Fresh stopped-state report was not received.'
    } finally {
        if ($check.IsOpen) { $check.Close() }; $check.Dispose()
    }
}
function Reset-G474([string]$Label) {
    $stopped = Confirm-Pause
    if ($stopped.state -ne 'PAUSED' -or $stopped.pending -ne 0) { throw 'Unsafe reset baseline.' }
    $output = & $Programmer -c port=SWD "sn=$G474Serial" mode=HOTPLUG freq=1000 -rst 2>&1
    $exitCode = $LASTEXITCODE
    $safe = ($output | Where-Object { $_ -notmatch 'ST-LINK SN' }) -join "`n"
    [IO.File]::WriteAllText((Join-Path $RunDirectory "$Label-g474-reset.txt"),$safe)
    if ($exitCode -ne 0) { throw 'G474 software reset failed.' }
    Start-Sleep -Milliseconds 500
    $boot = Confirm-Pause
    if ($boot.state -ne 'PAUSED' -or $boot.pending -ne 0) { throw 'G474 did not boot into idle.' }
    Progress "G474 software reset ${Label}: booted paused; no reflash."
}
function Stage([string]$Name,[int]$Rate,[int]$Duration,[int]$Hold) {
    if (Test-Path -LiteralPath $cancelFile) { throw 'STOP file requested cancellation.' }
    $suite.current_stage=$Name; Save-Suite
    Progress "Starting $Name ($Duration seconds at $Rate requested pairs/s)."
    $stageDir = Join-Path $RunDirectory $Name
    & (Join-Path $PSScriptRoot 'run-link-test.ps1') -Rate $Rate -RunDirectory $stageDir -Programmer $Programmer -F303Serial $F303Serial -Port $Port -Seconds $Duration -MaxSeconds ($Duration+30) -PauseHoldSeconds $Hold -CancelFile $cancelFile
    $result=Get-Content -LiteralPath (Join-Path $stageDir "stage-$Rate.json") -Raw | ConvertFrom-Json
    if (-not $result.pass) { throw "$Name failed." }
    $stages.Add([pscustomobject]@{
        name=$Name; requested_pairs_per_second=$Rate; observed_pairs_per_second=$result.observed_echo_pairs_per_second;
        seconds=$result.run_seconds; pairs=$result.g474.echo; max_rtt_us=$result.g474.rtt_max_us;
        missed_pacing_intervals=$result.g474.late; pause_hold_seconds=$Hold; pass=$result.pass;
        evidence="$Name/stage-$Rate.json"
    })
    Save-Suite
    Progress "PASS ${Name}: $($result.g474.echo) matched pairs; idle hold passed."
}
Save-Suite
Progress 'Bounded lunch suite started. IDs 0x601/0x602 only; no motors, no firmware writes.'
try {
    # Four MCU software-reset cycles; each sub-stage also resets F303 while G474 is paused.
    for ($cycle=1;$cycle -le 4;$cycle++) {
        Reset-G474 "cycle-$cycle"
        foreach ($rate in @(100,1000,2500)) {
            Stage "cycle-$cycle-rate-$rate" $rate 8 3
        }
    }
    Stage 'soak-2500' 2500 $SoakSeconds 5
    $suite.state='COMPLETED'; $suite.pass=$true
    Progress 'All 12 functionality stages and the high-load soak passed.'
} catch {
    $suite.state='FAILED'; $suite.error=$_.Exception.Message
    Progress "STOP: $($suite.error) No automatic retry or fault clearing."
} finally {
    try {
        $suite.final_pause=Confirm-Pause
        Progress "Final stopped state confirmed: $($suite.final_pause.state), pending=$($suite.final_pause.pending)."
        if ($suite.final_pause.state -ne 'PAUSED' -or $suite.final_pause.pending -ne 0) {
            $suite.state='FAILED'; $suite.pass=$false
            if (-not $suite.error) { $suite.error='Final state is not clean paused idle.' }
        }
    } catch {
        $suite.final_pause=[ordered]@{confirmed=$false;error=$_.Exception.Message}
        $suite.state='FAILED'; $suite.pass=$false
        if (-not $suite.error) { $suite.error='Could not confirm final stopped state.' }
        Progress 'WARNING: final pause could not be confirmed; inspect hardware before using it.'
    }
    $suite.finished=[DateTimeOffset]::Now.ToString('o'); Save-Suite
    $rows = @('# Extended 1 Mbit/s bench test', '', "State: $($suite.state)", "Verified request/echo pairs: $($suite.total_verified_pairs)", '', '| Stage | Requested pairs/s | Observed pairs/s | Verified pairs | Seconds | Verdict |', '| --- | ---: | ---: | ---: | ---: | --- |')
    foreach ($item in $stages) { $rows += "| $($item.name) | $($item.requested_pairs_per_second) | $($item.observed_pairs_per_second) | $($item.pairs) | $($item.seconds) | PASS |" }
    $rows += @('', 'All stages check the full eight-byte payload and outstanding sequence, reconcile independent F303 SWD counters, and require zero recorded protocol/data/timeout/queue/FIFO faults. Each stage includes a paused-idle hold. Start commands restart/reset G474 CAN test counters; this is not sequence-preserving resume. MCU software resets are not cold power cycles.', '', "Final stop confirmation: $($suite.final_pause.confirmed); state: $($suite.final_pause.state).", "Error: $($suite.error)", '', 'Missed pacing intervals are host/firmware scheduling misses, not lost CAN frames. Use actual throughput. No physical fault injection, motor noise, temperature sweep or analogue waveform capture is included. Zero observed faults is not a guarantee of zero error probability.')
    [IO.File]::WriteAllText((Join-Path $RunDirectory 'README.md'),($rows -join "`r`n"))
}
if (-not $suite.pass) { exit 1 }
