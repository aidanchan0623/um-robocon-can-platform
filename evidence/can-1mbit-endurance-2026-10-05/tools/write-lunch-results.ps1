param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference='Stop'
$suite=Get-Content -LiteralPath (Join-Path $RunDirectory 'suite.json') -Raw | ConvertFrom-Json
if ($suite.state -ne 'COMPLETED' -or -not $suite.pass -or $suite.stages.Count -ne 13 -or
    -not $suite.final_pause.confirmed -or $suite.final_pause.state -ne 'PAUSED' -or $suite.final_pause.pending -ne 0) {
    throw 'Suite is not complete with 13 passing stages and confirmed idle.'
}
$audit=[Collections.Generic.List[object]]::new()
$sum=0L
$gErrors='bad','unexpected','timeout','qfail','rx_lost','tef_lost','err_events','bo_events','tec','rec','tec_max','rec_max','lec','uart_err'
$fErrors='invalid','queue_overflow','rx_overrun','tx_failed','hal_fail','error_events','bus_off','tec','rec','max_tec','max_rec','last_error'
$fNames='magic','ready','polls','received','queued','completed','invalid','queue_overflow','rx_overrun','tx_failed','hal_fail','error_events','bus_off','tec','rec','max_tec','max_rec','last_error','pending'
foreach ($stage in $suite.stages) {
    $jsonPath=Join-Path $RunDirectory $stage.evidence
    $result=Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    if (-not $result.pass -or -not $result.totals_match -or -not $result.pause_hold_passed -or $result.g474.state -ne 'PAUSED') { throw "Stage invalid: $($stage.name)" }
    $total=$result.g474.echo
    foreach ($value in @($result.g474.queued,$result.g474.tx_done,$result.f303_after.received,$result.f303_after.queued,$result.f303_after.completed,$stage.pairs)) {
        if ($value -ne $total) { throw 'Independent final totals disagree.' }
    }
    if ($result.g474.pending -ne 0 -or $result.f303_after.pending -ne 0) { throw 'Pending replies remain.' }
    foreach ($field in $gErrors) { if ($result.g474.$field -ne 0) { throw "G474 $field nonzero." } }
    foreach ($field in $fErrors) { if ($result.f303_after.$field -ne 0) { throw "F303 $field nonzero." } }
    $stem=Join-Path (Split-Path $jsonPath) ('stage-'+$stage.requested_pairs_per_second)
    $serialLast=@(Get-Content -LiteralPath "$stem-serial.txt" | Where-Object { $_ -match 'CAN1M G474 state=' })[-1]
    if ($serialLast -notmatch 'state=PAUSED') { throw 'Raw serial record is not paused.' }
    foreach ($match in [regex]::Matches($serialLast,'\b([a-z_]+)=(\d+)\b')) {
        $key=$match.Groups[1].Value
        if ($result.g474.$key -ne [long]$match.Groups[2].Value) { throw "Raw serial differs: $key" }
    }
    foreach ($label in @('before','after')) {
        $raw=Get-Content -LiteralPath "$stem-f303-$label.txt"
        $words=[Collections.Generic.List[long]]::new()
        foreach ($line in $raw) {
            if ($line -match '^0x20000[0-9A-Fa-f]+\s*:\s*(.+)$') {
                foreach ($hex in ($Matches[1].Trim() -split '\s+')) {
                    if ($hex -match '^[0-9A-Fa-f]{8}$') { $words.Add([Convert]::ToUInt32($hex,16)) }
                }
            }
        }
        if ($words.Count -ne 19) { throw 'Wrong SWD record length.' }
        $expected=$result.('f303_'+$label)
        for ($i=0;$i -lt 19;$i++) { if ($expected.($fNames[$i]) -ne $words[$i]) { throw 'Raw SWD record differs from JSON.' } }
    }
    $audit.Add([pscustomobject]@{stage=$stage.name;pairs=$total;raw_serial_matches=$true;raw_swd_before_matches=$true;raw_swd_after_matches=$true;all_totals_match=$true;zero_error_counters=$true;pause_hold_passed=$true})
    $sum += $total
}
if ($sum -ne $suite.total_verified_pairs) { throw 'Suite sum mismatch.' }
$soak=Get-Content -LiteralPath (Join-Path $RunDirectory 'soak-2500/stage-2500.json') -Raw | ConvertFrom-Json
if ($soak.run_seconds -lt 1800) { throw 'Soak shorter than 30 minutes.' }
[IO.File]::WriteAllText((Join-Path $RunDirectory 'verification-audit.json'),([ordered]@{verified_at=[DateTimeOffset]::Now.ToString('o');checked_stages=$audit.ToArray();total_pairs=$sum;raw_records_reconciled=$true} | ConvertTo-Json -Depth 8))
$summary=@(
    'CAN 1 Mbit/s - extended bench-test results',
    'UM Robocon | 5 October 2026 | G474 <-> F303',
    '',
    'PASS: all 12 functionality stages + 30-minute high-load soak',
    'Classic CAN | IDs 0x601 / 0x602 | 8-byte sequence and patterns',
    'External transceiver boards and physical CAN link; not loopback',
    '',
    ('30-minute soak verified pairs: {0:N0}' -f $soak.g474.echo),
    ('All extended stages total:    {0:N0} pairs / {1:N0} CAN frames' -f $sum,($sum*2)),
    ('Measured soak rate:           {0:N2} pairs/s ({1} requested)' -f $soak.observed_echo_pairs_per_second,$soak.requested_pairs_per_second),
    ('Soak duration:                {0:N3} seconds' -f $soak.run_seconds),
    ('Max application round trip:   {0} us (includes software)' -f $soak.g474.rtt_max_us),
    '',
    'G474 queued / completed / byte-validated replies:',
    ('{0:N0} / {1:N0} / {2:N0}' -f $soak.g474.queued,$soak.g474.tx_done,$soak.g474.echo),
    'Independent F303 received / queued / completed:',
    ('{0:N0} / {1:N0} / {2:N0}' -f $soak.f303_after.received,$soak.f303_after.queued,$soak.f303_after.completed),
    '',
    'Wrong bytes / sequence / timeouts / queue / FIFO errors: ZERO',
    'Recorded CAN protocol errors / bus-off / max TEC / REC: ZERO',
    '4 G474 software resets; 13 F303 software resets; idle holds PASS',
    'Final state: PAUSED | pending=0 | runner finished',
    '',
    ('Soak pacing misses: {0}; scheduling misses, NOT lost CAN frames.' -f $soak.g474.late),
    'Limits: two-node bench only; no motors, EMI, cold power or EMC.',
    'Report generated from raw serial/SWD records; not a bus trace.',
    'Zero observed errors does not guarantee zero error probability.'
)
[IO.File]::WriteAllText((Join-Path $RunDirectory 'Extended-Results.txt'),($summary -join "`r`n"))
$doc=@('# Extended 1 Mbit/s Classic CAN validation — 5 October 2026','',
    '**PASS:** 12 short functionality stages and a 30-minute high-load soak through the external-MCU transceiver-board setup.',
    '',("The soak verified **{0:N0} eight-byte request/echo pairs**; the complete extended suite verified **{1:N0} pairs / {2:N0} delivered CAN data frames**. All 13 stages reconciled G474 queued/TX/validated-reply totals against independently read F303 RX/queued/TX totals, with no pending replies or recorded data, sequence, timeout, queue, FIFO or controller errors." -f $soak.g474.echo,$sum,($sum*2)),
    '', '## Test method','',
    'The existing firmware sends standard-ID 0x601 eight-byte frames containing a sequence and changing patterns (all zeros, all ones, 0x55, 0xAA and sequence-derived patterns). F303 echoes all eight bytes using ID 0x602. G474 checks every reply byte and its outstanding sequence. Both controllers use normal mode at 1 Mbit/s with automatic retransmission; the firmware is unchanged from the earlier validation.',
    '',
    'Four G474 software-reset cycles each include short runs at requested 100, 1,000 and 2,500 pairs/s. Each of the 13 stages resets F303 only while G474 is paused and checks its zero baseline. After each run, queued traffic drains, G474 remains paused for 3 seconds (5 after the soak), and its counters must remain unchanged with zero pending replies. Final F303 counters are independently read over SWD. Start commands restart the CAN test and reset its sequence/counters; this is not sequence-preserving resume. These are software resets, not cold power cycles.',
    '', '## Recorded stages','',
    '| Stage | Requested pairs/s | Observed pairs/s | Verified pairs | Run seconds | Verdict |',
    '| --- | ---: | ---: | ---: | ---: | --- |')
foreach ($stage in $suite.stages) { $doc += "| $($stage.name) | $($stage.requested_pairs_per_second) | $($stage.observed_pairs_per_second) | $($stage.pairs) | $($stage.seconds) | PASS |" }
$doc += @('', '## Interpretation and limits','',
    ("The 30-minute run lasted {0} seconds and achieved approximately **{1} pairs/s**, not exactly the requested 2,500. Its **{2} missed pacing intervals** are firmware scheduling misses, not missing CAN frames. Maximum application round trip was {3} microseconds, including software/queues, not transceiver propagation delay or motor response time." -f $soak.run_seconds,$soak.observed_echo_pairs_per_second,$soak.g474.late,$soak.g474.rtt_max_us),
    '',
    'Observed rates are estimates using host receipt timestamps of roughly once-per-second serial reports; buffering affects short-stage estimates (notably cycle-2-rate-100). Byte counts and final independent reconciliations are the integrity evidence. No per-frame bus capture is included.',
    '',
    'This is a two-node room-temperature bench result, not qualification for four ESCs, a complete robot harness, motor-switching noise, environmental extremes or EMC. Cable length and temperature were not measured. Both MCUs use internal oscillators; their tolerance across voltage/temperature was not tested. Earlier termination near 60 ohms was reported by the user, not independently remeasured for this test. No motors were commanded, no components or wiring were changed, and no physical fault injection or cold power cycling was performed. Zero recorded errors is not an absolute guarantee.',
    '', '## Provenance and evidence','',
    'A host-script syntax error prevented the first runner launch before any hardware access. It was corrected before the successful suite; the private original launch/error logs remain in the local run directory and are omitted from the publication bundle because they contain host paths. No hardware fault was retried or cleared.',
    '',
    '- `suite.json`: final stage summary and fresh PAUSED confirmation.',
    '- `verification-audit.json`: all 13 final records checked against their raw serial and before/after SWD records.',
    '- `cycle-*/` and `soak-2500/`: raw timestamped serial logs, diagnostic CSV, JSON verdict and independent F303 reads.',
    '- `cycle-*-g474-reset.txt`: G474 software-reset records, with probe serial numbers removed.',
    '- `final-pause-serial.txt`: final stopped-state report; `live-progress.txt`: suite progress.',
    '- `baseline-firmware-identification.json`: earlier tested firmware hashes and nominal configuration; its timestamp belongs to that earlier run.',
    '- `tools/`: exact host test scripts used; probe identifiers are supplied by the operator as parameters.',
    '- `Extended-Results.txt`: generated report for the unedited screenshot below, not an oscilloscope or CAN-analyser trace.',
    '',
    '![Extended test results report](extended-results-screenshot.jpg)',
    '', '## Reproduce','',
    'Use the [earlier source overlays and binary-reproduction procedure](../can-1mbit-2026-10-05/REPRODUCTION.md) for the same firmware. With those binaries already flashed to the correct boards, run `tools/run-lunch-suite.ps1` in PowerShell 7 with a new `-RunDirectory`, the installed `-Programmer` path, your explicit `-G474Serial` and `-F303Serial`, the G474 diagnostic `-Port`, and `-SoakSeconds 1800`. This contacts hardware, starts synthetic traffic and performs MCU software resets; disconnect motor controllers first. Do not run a second serial client or test runner concurrently.',
    '',
    'The runner stops on detected faults or a `STOP` file in its run directory, attempts to pause in its cleanup, and records final stop confirmation. Keep power/USB/computer available; abrupt host loss can prevent cleanup. This is not a physical emergency stop. AI assisted firmware/host diagnostics and evidence preparation; Aidan performed the hardware assembly diagnosis and measurements.')
[IO.File]::WriteAllText((Join-Path $RunDirectory 'PUBLIC-REPORT.md'),($doc -join "`r`n"))
Write-Output "Audited all 13 stages against raw records; $sum verified pairs; final pause confirmed."
