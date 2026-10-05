param([Parameter(Mandatory=$true)][string]$RunDirectory)
$ErrorActionPreference = 'Stop'
$results = @(100,1000,2500 | ForEach-Object {
    $path = Join-Path $RunDirectory "stage-$_.json"
    if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
})
$complete = $results.Count -eq 3
$allPass = $complete -and @($results | Where-Object { -not $_.pass }).Count -eq 0
$total = [long](($results | ForEach-Object { $_.g474.echo } | Measure-Object -Sum).Sum)
$summary = [Collections.Generic.List[string]]::new()
$summary.Add('CAN 1 Mbit/s - application integrity bench validation')
$summary.Add('UM Robocon CAN platform | 5 October 2026 | Aidan and Rui Leong')
$summary.Add('')
$summary.Add($(if($allPass){'RESULT: ALL THREE STAGES PASSED'}elseif($complete){'RESULT: CHECK FAILED STAGES'}else{'RESULT: TEST STILL IN PROGRESS - completed stages shown only'}))
$summary.Add('NUCLEO-G474RE -> custom CAN boards -> NUCLEO-F303RE -> echo')
$summary.Add('Classic CAN | standard IDs 0x601 / 0x602 | 8 bytes | 1 Mbit/s')
$summary.Add('Both controllers: 75% sample point, normal mode, auto retry')
$summary.Add('')
$summary.Add('Requested   Observed    Verified pairs   Seconds   Result')
$summary.Add('pairs/s     pairs/s')
foreach ($r in $results) {
    $summary.Add(('{0,-12}{1,-12:N2}{2,-17:N0}{3,-10:N1}{4}' -f $r.requested_pairs_per_second,$r.observed_echo_pairs_per_second,$r.g474.echo,$r.run_seconds,$(if($r.pass){'PASS'}else{'FAIL'})))
}
$summary.Add('')
$summary.Add(('TOTAL VERIFIED: {0:N0} request/echo pairs ({1:N0} CAN frames)' -f $total,($total*2)))
$summary.Add('Each reply checked byte-for-byte and against a pending sequence.')
$summary.Add('After pause/drain: queued = transmitted = echoed on G474,')
$summary.Add('and independently matches F303 received/transmitted totals.')
$summary.Add('')
$summary.Add('Evidence: timestamped serial logs, CSV, JSON and F303 SWD reads.')
$summary.Add('This screenshot is a report of those logs, not a bus waveform.')
$summary.Add('Limit: two-node bench result; not motor-noise, temperature or')
$summary.Add('four-ESC qualification. Zero observed errors is not a guarantee.')
[IO.File]::WriteAllLines((Join-Path $RunDirectory 'CAN1M-Summary.txt'),$summary,[Text.UTF8Encoding]::new($false))
if ($results.Count -gt 0) {
    $r = $results[-1]; $g=$r.g474; $f=$r.f303_after
    $detail = @(
        'CAN 1 Mbit/s - independently reconciled final counters',
        ('Stage: {0} requested pairs/s | {1:N2} observed pairs/s' -f $r.requested_pairs_per_second,$r.observed_echo_pairs_per_second),
        ('Run started: {0}' -f $r.started),
        ('Run ended:   {0}' -f $r.finished),
        '',
        ('G474 queued / TX / valid echoes: {0:N0} / {1:N0} / {2:N0}' -f $g.queued,$g.tx_done,$g.echo),
        ('F303 RX / queued / TX:          {0:N0} / {1:N0} / {2:N0}' -f $f.received,$f.queued,$f.completed),
        ('Pending software replies: G474={0}, F303={1}' -f $g.pending,$f.pending),
        '',
        'Counter                               G474       F303',
        ('Wrong bytes / invalid frame           {0,-11}{1}' -f $g.bad,$f.invalid),
        ('Unexpected sequence                   {0,-11}n/a' -f $g.unexpected),
        ('Reply timeout                         {0,-11}n/a' -f $g.timeout),
        ('Queue failure / overflow              {0,-11}{1}' -f $g.qfail,$f.queue_overflow),
        ('RX FIFO loss / overrun                {0,-11}{1}' -f $g.rx_lost,$f.rx_overrun),
        ('Observed protocol errors              {0,-11}{1}' -f $g.err_events,$f.error_events),
        ('Bus-off events / observed flag        {0,-11}{1}' -f $g.bo_events,$f.bus_off),
        ('Observed maximum TEC                  {0,-11}{1}' -f $g.tec_max,$f.max_tec),
        ('Observed maximum REC                  {0,-11}{1}' -f $g.rec_max,$f.max_rec),
        '',
        ('Max application round trip: {0} us (includes software/queues)' -f $g.rtt_max_us),
        ('G474 missed pacing intervals: {0}; UART diagnostic errors: {1}' -f $g.late,$g.uart_err),
        'Pacing misses are not missing CAN frames; use measured rate.',
        ('State: {0} | All totals match: {1} | Verdict: {2}' -f $g.state,$r.totals_match,$(if($r.pass){'PASS'}else{'FAIL'}))
    )
    [IO.File]::WriteAllLines((Join-Path $RunDirectory 'CAN1M-Counters.txt'),$detail,[Text.UTF8Encoding]::new($false))
}
$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add('# 1 Mbit/s Classic CAN bench validation — 5 October 2026')
$markdown.Add('')
$markdown.Add($(if($allPass){'All three recorded stages passed the defined application-integrity criteria.'}else{'This run is incomplete or has failed stages; do not cite it as an all-stage pass.'}))
$markdown.Add('')
$markdown.Add('| Requested pairs/s | Observed pairs/s | Verified pairs | Run seconds | Max round trip (us) | Missed pacing intervals | Verdict |')
$markdown.Add('| ---: | ---: | ---: | ---: | ---: | ---: | --- |')
foreach ($r in $results) {
    $markdown.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $r.requested_pairs_per_second,$r.observed_echo_pairs_per_second,$r.g474.echo,$r.run_seconds,$r.g474.rtt_max_us,$r.g474.late,$(if($r.pass){'PASS'}else{'FAIL'})))
}
$markdown.Add('')
$markdown.Add(('Across completed stages: **{0:N0} byte-validated request/echo pairs**, equivalent to {1:N0} successfully delivered Classic CAN data frames.' -f $total,($total*2)))
$markdown.Add('')
$markdown.Add('## Method and pass criteria')
$markdown.Add('')
$markdown.Add('G474 sends standard-ID 0x601 eight-byte frames. F303 echoes exactly those eight bytes on ID 0x602. Bytes 0–3 are a big-endian sequence; bytes 4–7 rotate through zeros, ones, alternating 0x55/0xAA, sequence-derived and deterministic mixed patterns. G474 checks the full reply against the expected payload and outstanding sequence. CAN normal-mode automatic retransmission is enabled; this is not internal loopback.')
$markdown.Add('')
$markdown.Add('The G474 is paused between stages. F303 is reset and its baseline counters checked over SWD. Each stage starts with reset G474 counters. After the run, G474 is paused, queued replies are allowed to drain, and independent F303 counters are read without resetting the board. Pass requires equal nonzero G474 queued/completed/validated-echo totals, matching F303 received/queued/completed totals, no pending replies, and zero recorded payload, sequence, timeout, FIFO, queue, protocol, bus-off and observed maximum TEC/REC faults on both sides. Diagnostic UART errors must also be zero.')
$markdown.Add('')
$markdown.Add('## Results and limitations')
$markdown.Add('')
$markdown.Add('Use measured throughput, not the configured rate. The G474 firmware runs at 16 MHz and builds an interrupt-driven UART status report once per second; the achieved request rate is below the requested high-load setting. Its `late` counter counts missed scheduling intervals, not dropped or corrupted CAN frames. It is not grounds for claiming exact 2,500 pairs/s sustained throughput. The application round-trip maximum includes software execution and mailbox/queue latency; it is not a measured transceiver propagation delay or a motor response time.')
$markdown.Add('')
$markdown.Add('This is a two-node bench test through the user-built transceiver boards. It does not qualify four physical ESC nodes, a complete robot harness, motor-switching noise, long cables, environmental conditions or EMC. Both MCUs use internal oscillators; clock tolerance across voltage/temperature was not tested. Cable length and ambient temperature were not measured. Earlier termination was reported by the user near 60 ohms, not independently remeasured during this run. A pass means no faults were observed by the stated application checks and controller counters under these conditions; it does not prove that every analogue edge is ideal or that the error probability is literally zero.')
$markdown.Add('')
$markdown.Add('There was one aborted host-side preflight before the 1,000-pair/s stage: buffered PAUSED reports from the prior stage were accepted before the new rate was confirmed. The host script was corrected to wait for the expected rate and zero queued count. The preflight evidence is retained under `stage-1000-preflight1-*`; no RUN command was sent in that aborted attempt. Firmware was not changed or reflashed during this validation.')
$markdown.Add('')
$markdown.Add('## Evidence files')
$markdown.Add('')
$markdown.Add('- `manifest.json`: firmware SHA-256 hashes and nominal controller configuration.')
$markdown.Add('- `stage-*-serial.txt`: raw G474 status messages with host receipt timestamps; approximately one report per second, not a per-frame CAN capture.')
$markdown.Add('- `stage-*-samples.csv`: parsed diagnostic samples.')
$markdown.Add('- `stage-*.json`: reconciled final stage totals, observed throughput and pass criteria.')
$markdown.Add('- `stage-*-f303-before.txt` / `after.txt`: independent SWD memory reads. Probe serial numbers are removed from these published copies.')
$markdown.Add('- `CAN1M-Summary.txt` / `CAN1M-Counters.txt`: readable reports generated from the stage JSON, for screenshot capture. Screenshots are report-viewer captures, not oscilloscope or CAN-analyser traces.')
$markdown.Add('- `live-progress.txt`: complete read-only-terminal progress history, including the aborted preflight.')
$markdown.Add('')
$markdown.Add('Follow-up work: higher-clock or hardware-timed pacing, independent analyser/oscilloscope captures, repeated cold starts, cable-length testing, and multi-node/noisy motor-operation tests. The synthetic IDs used here are not VESC or C620 motor commands.')
[IO.File]::WriteAllLines((Join-Path $RunDirectory 'README.md'),$markdown,[Text.UTF8Encoding]::new($false))
Write-Host "Updated report for $($results.Count) completed stages: $RunDirectory"
