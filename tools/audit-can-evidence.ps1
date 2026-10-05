# Offline evidence audit only: no programmer, serial port, reset or CAN traffic.
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$roots = @('evidence/can-1mbit-2026-10-05','evidence/can-1mbit-endurance-2026-10-05')
$names = @('magic','ready','polls','received','queued','completed','invalid',
    'queue_overflow','rx_overrun','tx_failed','hal_fail','error_events',
    'bus_off','tec','rec','max_tec','max_rec','last_error','pending')
$gErrors = @('bad','unexpected','timeout','qfail','rx_lost','tef_lost',
    'err_events','bo_events','tec','rec','tec_max','rec_max','lec','uart_err')
$fErrors = @('invalid','queue_overflow','rx_overrun','tx_failed','hal_fail',
    'error_events','bus_off','tec','rec','max_tec','max_rec','last_error')
$records = [Collections.Generic.List[object]]::new()
$preRunUartReports = 0

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-RawSWD([string]$Path) {
    $words = [Collections.Generic.List[uint32]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^0x20000[0-9A-Fa-f]+\s*:\s*(.+)$') {
            foreach ($hex in ($Matches[1].Trim() -split '\s+')) {
                if ($hex -match '^[0-9A-Fa-f]{8}$') { $words.Add([Convert]::ToUInt32($hex,16)) }
            }
        }
    }
    Require ($words.Count -eq $names.Count) "Unexpected SWD word count: $Path"
    $values = [ordered]@{}
    for ($i=0; $i -lt $names.Count; $i++) { $values[$names[$i]] = [long]$words[$i] }
    return [pscustomobject]$values
}
function Read-RawStatus([string]$Line) {
    Require ($Line -match 'CAN1M G474 state=(RUN|PAUSED|FAULT) ') 'Missing G474 status'
    $values = [ordered]@{state=$Matches[1]}
    foreach ($match in [regex]::Matches($Line,'\b([a-z_]+)=(\d+)\b')) {
        $values[$match.Groups[1].Value] = [long]$match.Groups[2].Value
    }
    return [pscustomobject]$values
}
function Compare-Values($Expected,$Actual,[string]$Label) {
    foreach ($property in $Expected.PSObject.Properties) {
        if ($property.Name -eq 'timestamp') { continue }
        Require ($null -ne $Actual.PSObject.Properties[$property.Name]) "Missing $Label/$($property.Name)"
        Require ($property.Value -eq $Actual.($property.Name)) "Mismatch $Label/$($property.Name)"
    }
}

foreach ($root in $roots) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot $root) -Recurse -Filter 'stage-*.json' -File)
    $expectedCount = if ($root -eq $roots[0]) { 3 } else { 13 }
    Require ($files.Count -eq $expectedCount) "Stage count changed: $root"
    foreach ($file in $files) {
        $r = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        Require ($r.pass -and $r.totals_match) "Recorded verdict failed: $($file.Name)"
        $stem = $file.FullName.Substring(0,$file.FullName.Length-5)
        $lines = @(Get-Content -LiteralPath ($stem+'-serial.txt') | Where-Object { $_ -match 'CAN1M G474 state=' })
        Require ($lines.Count -gt 0) "Missing serial evidence: $stem"
        $last = Read-RawStatus $lines[-1]
        Compare-Values $r.g474 $last "$stem/G474"
        Require ($last.state -eq 'PAUSED' -and $last.bitrate -eq 1000000) "Wrong final state/bitrate: $stem"
        foreach ($side in @('before','after')) {
            $raw = Read-RawSWD ($stem+'-f303-'+$side+'.txt')
            Compare-Values $r.('f303_'+$side) $raw "$stem/F303-$side"
            Require ($raw.magic -eq 0x43414E32 -and $raw.ready -eq 1) "Wrong F303 layout/readiness: $stem"
        }
        foreach ($name in @('received','queued','completed','pending')+$fErrors) {
            Require ($r.f303_before.$name -eq 0) "Nonzero F303 baseline $name : $stem"
        }
        foreach ($name in $gErrors) { Require ($last.$name -eq 0) "G474 fault $name : $stem" }
        foreach ($name in $fErrors) { Require ($r.f303_after.$name -eq 0) "F303 fault $name : $stem" }
        $counts = @($last.queued,$last.tx_done,$last.echo,$r.f303_after.received,
            $r.f303_after.queued,$r.f303_after.completed) | Select-Object -Unique
        Require (@($counts).Count -eq 1 -and $counts[0] -gt 0) "Unequal traffic counts: $stem"
        Require ($last.pending -eq 0 -and $r.f303_after.pending -eq 0) "Outstanding traffic: $stem"
        $firstRun = -1
        for ($i=0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'state=RUN ') { $firstRun=$i; break }
            $preRun = Read-RawStatus $lines[$i]
            if ($preRun.uart_err -gt 0) { $preRunUartReports++ }
        }
        Require ($firstRun -ge 0) "No recorded RUN status: $stem"
        foreach ($line in $lines[$firstRun..($lines.Count-1)]) {
            $sample = Read-RawStatus $line
            Require ($sample.state -ne 'FAULT') "Fault in raw serial history: $stem"
            foreach ($name in $gErrors) { Require ($sample.$name -eq 0) "Historical G474 fault $name : $stem" }
        }
        if ($root -eq $roots[1]) {
            Require ($r.pause_hold_passed -and $r.pause_hold_seconds -ge 3) "Idle hold failed: $stem"
            $paused = @($lines | Where-Object { $_ -match 'state=PAUSED ' -and $_ -match "echo=$($last.echo) " })
            Require ($paused.Count -ge 2) "Insufficient idle history: $stem"
            $firstTime = [DateTimeOffset]::Parse(($paused[0] -split ' ',2)[0])
            $lastTime = [DateTimeOffset]::Parse(($paused[-1] -split ' ',2)[0])
            # Reports arrive roughly once per second; their sampled span can be
            # shorter than the host stopwatch hold. Corroborate within one
            # report interval; this is not continuous independent observation.
            Require (($lastTime-$firstTime).TotalSeconds -ge ($r.pause_hold_seconds-1.2)) "Insufficient sampled idle span: $stem"
            foreach ($line in $paused) { Compare-Values $r.g474 (Read-RawStatus $line) "$stem/idle" }
        }
        $records.Add([pscustomobject]@{path=$file.FullName;pairs=[long]$last.echo;seconds=$r.run_seconds})
    }
}
$suiteRoot = Join-Path $RepositoryRoot $roots[1]
$suite = Get-Content -LiteralPath (Join-Path $suiteRoot 'suite.json') -Raw | ConvertFrom-Json
Require ($suite.state -eq 'COMPLETED' -and $suite.pass -and $suite.stages.Count -eq 13) 'Incomplete suite'
foreach ($stage in $suite.stages) {
    $r = Get-Content -LiteralPath (Join-Path $suiteRoot $stage.evidence) -Raw | ConvertFrom-Json
    Require ($stage.pass -and $stage.pairs -eq $r.g474.echo -and $stage.seconds -eq $r.run_seconds) 'Suite/stage mismatch'
}
$soak = Get-Content -LiteralPath (Join-Path $suiteRoot 'soak-2500/stage-2500.json') -Raw | ConvertFrom-Json
Require ($soak.run_seconds -ge 1800 -and $soak.pause_hold_seconds -eq 5) 'Soak too short'
$final = Read-RawStatus (Get-Content -LiteralPath (Join-Path $suiteRoot 'final-pause-serial.txt') -Raw)
Compare-Values $soak.g474 $final 'Final pause'
Require ($suite.final_pause.confirmed -and $suite.final_pause.state -eq 'PAUSED' -and $suite.final_pause.pending -eq 0) 'Final pause unconfirmed'
$initialPairs = [long](($records | Where-Object path -Like '*can-1mbit-2026-10-05*' | Measure-Object pairs -Sum).Sum)
$extendedPairs = [long](($records | Where-Object path -Like '*can-1mbit-endurance-2026-10-05*' | Measure-Object pairs -Sum).Sum)
Require ($extendedPairs -eq $suite.total_verified_pairs) 'Suite total mismatch'
$total = $initialPairs+$extendedPairs
[pscustomobject]@{
    stages=$records.Count; initial_pairs=$initialPairs; extended_pairs=$extendedPairs;
    verified_pairs=$total; delivered_data_frames=2*$total;
    raw_serial_and_swd_reconciled=$true; recorded_errors=0;
    final_recorded_state=$final.state; pending=$final.pending;
    soak_seconds=$soak.run_seconds; soak_pairs_per_second=$soak.observed_echo_pairs_per_second;
    soak_missed_pacing_intervals=$soak.g474.late; max_soak_rtt_us=$soak.g474.rtt_max_us
    preparatory_reports_with_nonzero_uart_counter=$preRunUartReports
} | ConvertTo-Json
