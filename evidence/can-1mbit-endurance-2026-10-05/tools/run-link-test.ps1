param(
    [Parameter(Mandatory=$true)][ValidateSet(100,1000,2500)][int]$Rate,
    [Parameter(Mandatory=$true)][string]$RunDirectory,
    [Parameter(Mandatory=$true)][string]$Programmer,
    [Parameter(Mandatory=$true)][string]$F303Serial,
    [string]$Port = 'COM7',
    [int]$Seconds = 15,
    [int]$GoalPairs = 0,
    [int]$MaxSeconds = 600,
    [ValidateRange(0,30)][int]$PauseHoldSeconds = 0,
    [string]$CancelFile = ''
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null
$stage = Join-Path $RunDirectory "stage-$Rate"
if (Test-Path -LiteralPath "$stage.json") { throw 'Stage already recorded; choose another run directory.' }
$raw = [IO.StreamWriter]::new("$stage-serial.txt",$false,[Text.UTF8Encoding]::new($false))
$raw.AutoFlush = $true
$csv = [IO.StreamWriter]::new("$stage-samples.csv",$false,[Text.UTF8Encoding]::new($false))
$csv.AutoFlush = $true
$script:buffer = ''; $script:latest = $null; $script:samples = [Collections.Generic.List[object]]::new()
$progressPath = Join-Path $RunDirectory 'live-progress.txt'
function Progress([string]$Message) {
    $line = "$(Get-Date -Format 'HH:mm:ss')  $Message"
    Add-Content -LiteralPath $progressPath -Value $line
    Write-Host $line
}
function Read-Status {
    $script:buffer += $serial.ReadExisting()
    while ($script:buffer.Contains("`n")) {
        $index = $script:buffer.IndexOf("`n")
        $line = $script:buffer.Substring(0,$index).Trim()
        $script:buffer = $script:buffer.Substring($index+1)
        $now = [DateTimeOffset]::Now.ToString('o')
        $raw.WriteLine("$now $line")
        if ($line -notmatch '^CAN1M G474 state=(RUN|PAUSED|FAULT) ') { continue }
        $item = [ordered]@{timestamp=$now;state=$Matches[1]}
        foreach ($match in [regex]::Matches($line,'\b([a-z_]+)=(\d+)\b')) {
            $item[$match.Groups[1].Value] = [long]$match.Groups[2].Value
        }
        if ($item.bitrate -ne 1000000 -or $null -eq $item.echo) { throw 'Invalid firmware status.' }
        $script:latest = [pscustomobject]$item
        $script:samples.Add($script:latest)
        $values = $script:latest | ConvertTo-Csv -NoTypeInformation
        if ($script:samples.Count -eq 1) { $csv.WriteLine($values[0]) }
        $csv.WriteLine($values[1])
    }
}
function Wait-Status([string]$State,[int]$TimeoutSeconds=5,[int]$ExpectedRate=0,[switch]$RequireZero) {
    $script:latest = $null
    $waitTimer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Read-Status
        if ($null -ne $script:latest -and $script:latest.state -eq $State -and
            ($ExpectedRate -eq 0 -or $script:latest.rate -eq $ExpectedRate) -and
            (-not $RequireZero -or $script:latest.queued -eq 0)) { return }
        Start-Sleep -Milliseconds 30
    } while ($waitTimer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "No $State status received from G474."
}
function Read-F303([string]$Label) {
    $output = & $Programmer -c port=SWD "sn=$F303Serial" mode=HOTPLUG freq=1000 -r32 0x20000250 76 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'F303 diagnostic read failed.' }
    $safe = ($output | Where-Object { $_ -notmatch 'ST-LINK SN' }) -join "`n"
    [IO.File]::WriteAllText("$stage-f303-$Label.txt",$safe)
    $words = [Collections.Generic.List[uint32]]::new()
    foreach ($line in $output) {
        if ($line -match '^0x20000[0-9A-Fa-f]+\s*:\s*(.+)$') {
            foreach ($hex in ($Matches[1].Trim() -split '\s+')) {
                if ($hex -match '^[0-9A-Fa-f]{8}$') { $words.Add([Convert]::ToUInt32($hex,16)) }
            }
        }
    }
    $names = 'magic','ready','polls','received','queued','completed','invalid','queue_overflow','rx_overrun','tx_failed','hal_fail','error_events','bus_off','tec','rec','max_tec','max_rec','last_error','pending'
    if ($words.Count -ne $names.Count) { throw 'Unexpected F303 memory layout.' }
    $result = [ordered]@{}
    for ($i=0;$i -lt $names.Count;$i++) { $result[$names[$i]] = [long]$words[$i] }
    if ($result.magic -ne 0x43414E32 -or $result.ready -ne 1) { throw 'F303 echo firmware is not ready.' }
    return [pscustomobject]$result
}
$serial = [IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$serial.DtrEnable = $false; $serial.RtsEnable = $false
$stopReason = 'Not started'; $startTime = $null; $runTimer = $null; $f303Start = $null; $f303End = $null
try {
    $serial.Open()
    $serial.Write('P'); Wait-Status 'PAUSED'
    Progress "Preparing $Rate pairs/s. Resetting only the F303; G474 remains paused."
    $reset = & $Programmer -c port=SWD "sn=$F303Serial" mode=HOTPLUG freq=1000 -rst 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'F303 reset failed.' }
    Start-Sleep -Milliseconds 400
    $f303Start = Read-F303 'before'
    foreach ($name in 'received','queued','completed','invalid','queue_overflow','rx_overrun','tx_failed','hal_fail','error_events','bus_off','max_tec','max_rec') {
        if ($f303Start.$name -ne 0) { throw "Nonzero F303 baseline counter: $name" }
    }
    $select = if ($Rate -eq 100) {'1'} elseif ($Rate -eq 1000) {'2'} else {'3'}
    $serial.Write($select); Wait-Status -State 'PAUSED' -ExpectedRate $Rate -RequireZero
    if ($script:latest.rate -ne $Rate -or $script:latest.queued -ne 0) { throw 'Rate selection/reset not confirmed.' }
    $startTime = [DateTimeOffset]::Now.ToString('o')
    $serial.Write('S'); $runTimer = [Diagnostics.Stopwatch]::StartNew(); Wait-Status 'RUN'
    Progress "RUN $Rate pairs/s; checking all 8 echoed bytes, sequence, completion and error counters."
    $lastProgress = -5
    $stopReason = 'Duration completed'
    while ($true) {
        Read-Status
        if ($CancelFile -and (Test-Path -LiteralPath $CancelFile)) { $stopReason = 'Cancelled by stop file'; break }
        if ($script:latest.state -eq 'FAULT') { $stopReason = 'Firmware reported FAULT'; break }
        foreach ($field in 'bad','unexpected','timeout','qfail','rx_lost','tef_lost','err_events','bo_events','tec_max','rec_max','lec','uart_err') {
            if ($script:latest.$field -ne 0) { throw "Live diagnostic fault: $field" }
        }
        if ($runTimer.Elapsed.TotalSeconds -gt $MaxSeconds) { $stopReason = 'Time limit reached'; break }
        if ($GoalPairs -gt 0 -and $script:latest.echo -ge $GoalPairs) { $stopReason = 'Target pair count reached'; break }
        if ($GoalPairs -eq 0 -and $runTimer.Elapsed.TotalSeconds -ge $Seconds) { break }
        if ($runTimer.Elapsed.TotalSeconds - $lastProgress -ge 5) {
            $lastProgress = $runTimer.Elapsed.TotalSeconds
            Progress ("{0} pairs/s: {1:N0} echoes, bad={2}, timeout={3}, errors={4}, TECmax={5}, RECmax={6}" -f $Rate,$script:latest.echo,$script:latest.bad,$script:latest.timeout,$script:latest.err_events,$script:latest.tec_max,$script:latest.rec_max)
        }
        if ([DateTimeOffset]::Now - [DateTimeOffset]::Parse($script:latest.timestamp) -gt [TimeSpan]::FromSeconds(4)) {
            throw 'Live serial status stopped; test aborted.'
        }
        Start-Sleep -Milliseconds 30
    }
    $stopSeconds = $runTimer.Elapsed.TotalSeconds
    $serial.Write('P')
    Start-Sleep -Milliseconds 1200; Read-Status
    if ($script:latest.state -eq 'RUN') { throw 'G474 did not pause.' }
    $pauseHoldPassed = $true
    if ($PauseHoldSeconds -gt 0) {
        $pausedBaseline = $script:latest
        $pauseTimer = [Diagnostics.Stopwatch]::StartNew()
        while ($pauseTimer.Elapsed.TotalSeconds -lt $PauseHoldSeconds) {
            Read-Status
            if ($script:latest.state -ne 'PAUSED' -or $script:latest.pending -ne 0 -or
                $script:latest.queued -ne $pausedBaseline.queued -or
                $script:latest.tx_done -ne $pausedBaseline.tx_done -or
                $script:latest.echo -ne $pausedBaseline.echo) { $pauseHoldPassed = $false; break }
            Start-Sleep -Milliseconds 30
        }
        if ([DateTimeOffset]::Now - [DateTimeOffset]::Parse($script:latest.timestamp) -gt [TimeSpan]::FromSeconds(4)) {
            throw 'Paused heartbeat stopped.'
        }
        Progress "Paused-idle hold ${PauseHoldSeconds}s: counters unchanged=$pauseHoldPassed"
    }
    $f303End = Read-F303 'after'
    Read-Status
    $final = $script:latest
    $errorNames = 'bad','unexpected','timeout','qfail','rx_lost','tef_lost','err_events','bo_events','tec_max','rec_max','lec','uart_err'
    $g474Errors = @($errorNames | Where-Object { $final.$_ -ne 0 })
    $f303ErrorNames = 'invalid','queue_overflow','rx_overrun','tx_failed','hal_fail','error_events','bus_off','max_tec','max_rec','last_error'
    $f303Errors = @($f303ErrorNames | Where-Object { $f303End.$_ -ne 0 })
    $totalsMatch = $final.queued -eq $final.tx_done -and $final.tx_done -eq $final.echo -and $final.pending -eq 0 -and $f303End.received -eq $final.queued -and $f303End.queued -eq $final.queued -and $f303End.completed -eq $final.queued -and $f303End.pending -eq 0
    $pass = $final.state -eq 'PAUSED' -and $g474Errors.Count -eq 0 -and $f303Errors.Count -eq 0 -and $totalsMatch -and $pauseHoldPassed -and $final.echo -gt 0 -and $stopReason -notmatch 'FAULT|limit|Cancelled'
    $running = @($script:samples | Where-Object { $_.state -eq 'RUN' })
    $observedRate = $null
    if ($running.Count -ge 2) {
        $deltaTime = ([DateTimeOffset]::Parse($running[-1].timestamp)-[DateTimeOffset]::Parse($running[0].timestamp)).TotalSeconds
        if ($deltaTime -gt 0) { $observedRate = [Math]::Round(($running[-1].echo - $running[0].echo)/$deltaTime,2) }
    }
    $result = [ordered]@{
        started=$startTime; finished=[DateTimeOffset]::Now.ToString('o'); requested_pairs_per_second=$Rate;
        run_seconds=[Math]::Round($stopSeconds,3); observed_echo_pairs_per_second=$observedRate;
        goal_pairs=$GoalPairs; stop_reason=$stopReason; pass=$pass; totals_match=$totalsMatch;
        pause_hold_seconds=$PauseHoldSeconds; pause_hold_passed=$pauseHoldPassed;
        g474_error_fields=$g474Errors; f303_error_fields=$f303Errors;
        g474=$final; f303_before=$f303Start; f303_after=$f303End;
        evidence='Host-timestamped G474 serial reports and independent F303 SWD counters; not an oscilloscope or CAN analyser capture.'
    }
    [IO.File]::WriteAllText("$stage.json",($result | ConvertTo-Json -Depth 8))
    Progress ("{0} {1} pairs/s: G474 queued/TX/echo={2}/{3}/{4}; F303 RX/TX={5}/{6}; RTTmax={7} us; late={8}" -f $(if($pass){'PASS'}else{'FAIL'}),$Rate,$final.queued,$final.tx_done,$final.echo,$f303End.received,$f303End.completed,$final.rtt_max_us,$final.late)
    if (-not $pass) { throw "Stage failed. See $stage.json; do not escalate load." }
} catch {
    Progress "STOP: $($_.Exception.Message)"
    throw
} finally {
    if ($serial.IsOpen) { $serial.Write('P'); Start-Sleep -Milliseconds 100; $serial.Close() }
    $serial.Dispose(); $raw.Dispose(); $csv.Dispose()
}
