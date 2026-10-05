# Verification and current limits

The 1 Mbit/s results below exercised **two external Nucleo controllers through the custom transceiver boards**. The onboard STM32G431 was not the CAN controller under test. Its reported SWD recovery is documented separately and does not constitute an onboard CAN/PWM/encoder pass.

## 1 Mbit/s external-controller validation

On 5 October 2026, G474 sent eight-byte standard-ID `0x601` Classic CAN requests and F303 echoed them on `0x602`, in normal mode with automatic retransmission. Each request contained a big-endian sequence and a changing four-byte pattern. G474 validated every returned byte and matched the sequence to an outstanding request. Independent F303 RX/queued/TX counters were read over SWD after G474 paused and traffic drained.

| Dataset | Completed stages | Verified request/echo pairs | Evidence |
| --- | ---: | ---: | --- |
| Initial integrity test | 3 | 1,033,396 | [Stage JSON, serial/CSV and SWD reads](../evidence/can-1mbit-2026-10-05/README.md) |
| Extended functionality checks | 12 | 109,550 | [Four software-reset cycles at three rates](../evidence/can-1mbit-endurance-2026-10-05/README.md) |
| Extended soak | 1 | 4,188,005 | [1,800.024-second stage](../evidence/can-1mbit-endurance-2026-10-05/soak-2500/stage-2500.json) |
| **Total** | **16** | **5,330,951** | **10,661,902 delivered data frames** |

All completed stages reconciled G474 queued/TX/validated-reply counts with independently read F303 RX/queued/TX counts, with zero pending traffic and zero recorded payload, unexpected-sequence, timeout, queue/FIFO, protocol or bus-off faults. Observed TEC/REC maxima were zero. The extended runner confirmed **PAUSED, pending=0 at 13:15:58 +08:00**; this is a recorded final state, not a current hardware reading.

The publication audit repeats those checks against raw serial and SWD files:

```powershell
./tools/audit-can-evidence.ps1
```

This command is offline and does not reset or contact hardware. [Aggregate metadata](../evidence/can-validation-2026-10-05.json), [source/firmware provenance](firmware-provenance.md) and the [reproduction procedure](../evidence/can-1mbit-2026-10-05/REPRODUCTION.md) accompany the data.

### Why these checks were used

Zeros and ones in the pattern portion create runs that exercise CAN bit stuffing; alternating `0x55`/`0xAA` vary edge density. Sequence-derived and mixed patterns avoid relying on a single constant payload. The sequence/outstanding-request checks reject unknown or duplicate replies and expose missing replies through timeouts. Replies may arrive in any order within the 64-entry outstanding window: this firmware **does not assert strict receive ordering**. F303's independent counters corroborate delivery instead of relying only on the sender's accounting.

These checks verify the completed application exchanges; the serial files contain periodic diagnostic reports, not one captured CAN record per frame.

### Throughput, scheduling and latency

The soak achieved approximately **2,326.62 pairs/s**, or **4,653.24 delivered data frames/s**, at the requested 2,500 pairs/s. Its **1,804 missed pacing intervals** are firmware scheduling misses, not lost CAN frames. All requests actually queued still matched completed transmissions and validated echoes. Exact 2,500-pair/s sustained scheduling was not demonstrated.

Observed rates use the slope of validated-echo counts between host receipt timestamps of approximately once-per-second RUN reports. Serial buffering affects short-stage estimates, notably the 87.07-pair/s estimate in one 100-pair/s stage. Final integrity totals are reconciled separately.

The maximum recorded application round trip was **1,724 µs**. G474 samples `DWT->CYCCNT` before enqueueing a request, then subtracts that sample when its polling loop validates the corresponding echo, dividing by the nominal 16 MHz CPU clock. This includes software, transmit queues, both frame transmissions and F303 processing. It is not a transceiver propagation-delay measurement, a motor response time, a latency distribution or an independently calibrated worst-case bound. See [the timing implementation](../evidence/can-1mbit-2026-10-05/firmware-overlays/g474-can-ping/Core/Src/can_link_test.c).

### Derived bus-load estimate

An unstuffed eight-byte standard data frame occupies 108 bits through EOF, or **111 bits including the three-bit intermission**. Using a conservative 111–135-bit-per-frame allowance for variable stuffing gives:

```text
estimated load = 2 × 2326.62 frames/s × assumed bits/frame / 1,000,000 bits/s
               ≈ 51.65% to 62.82%
```

This is a derived estimate of successful-frame occupancy, not a measurement of utilisation or a claim about the exact maximum stuffed length. It excludes retransmissions/error/overload traffic and uses a host-estimated frame rate. Reference: [TI's CAN frame structure and stuffing overview](https://www.ti.com/lit/an/sloa101b/sloa101b.pdf).

### Prominent limits

- **Internal oscillators:** G474 used HSI at nominal 16 MHz; F303 used HSI/PLL with nominal PCLK1 at 32 MHz. Both used 16 time quanta, a 75% sample point and four-TQ SJW. Frequency error across temperature/voltage, cable propagation and transceiver delay were not qualified. Opposing clock errors compound, but an assumed ±1% per clock is not a measured error or a universal CAN tolerance limit. Allowable error depends on the timing and propagation budget; an HSE-based retest and a tolerance calculation remain future work. See [NXP AN1798, oscillator tolerance requirements](https://www.nxp.com/docs/en/application-note/AN1798.pdf).
- **Physical layer:** no independent per-frame analyser capture or 1 Mbit/s CANH/CANL edge photograph is included. Existing scope photos show SWD. Cable length and ambient temperature were not measured; termination near 60 ohms was operator-reported earlier, not remeasured during this run.
- **Coverage:** two nodes on a bench, no commanded motors, four ESCs, C620 application packets, cold power cycles, deliberate disconnections, temperature sweep, motor-switching noise or EMC testing. Software reset/start/stop checks are not cold starts or sequence-preserving resume.
- **Accounting limits:** automatic retransmission was enabled; periodic status and sampled error maxima are not independent wire-level evidence that every analogue edge was ideal or that lifetime error probability is zero.

### Preparation anomalies retained in the evidence

The initial 100-pair/s serial file contains **one UART diagnostic error counter in two PAUSED reports before counter reset and RUN**. The cause was not established; RUN and final reports recorded zero UART errors. This is distinct from CAN controller errors, and the raw reports are retained.

One host preflight before the 1,000-pair/s initial stage accepted buffered prior PAUSED reports. The host was corrected to confirm the intended rate and zero counters before sending RUN; the aborted preflight records are retained. The first extended runner launch had a host syntax error before hardware access, corrected before the successful launch. No hardware fault was retried or cleared during the completed suite.

## Historical milestones and motor observations

Dates are reconstructed from bench records rather than manufactured commit history. See [firmware provenance](firmware-provenance.md) for archived code identities and missing flash-time commit information.

| Milestone | Observation | Scope |
| --- | --- | --- |
| 24 September | Custom STM32 download-complete confirmation | One programming session, not full UART/CAN validation |
| Late September | G431 USART3 scope/adapter investigation | Clean UART terminal decoding not established in the selected archive |
| 27 September | G474 internal CAN loopback passed | Internal controller/configuration only |
| 30 September | G474/F303 normal-mode CAN success reported | MCU-to-MCU bench demonstration |
| Subsequent assembly diagnosis | Pressure-sensitive TCAN3413 contact repaired | External transceiver signal-path finding |
| 1 October | One BLDC, then two BLDCs operated through G474 CAN | Unloaded motor demonstrations |
| 5 October | 16 completed 1 Mbit/s stages above | External-MCU path only |
| 5 October | G431 flash success reported after SWDIO repair | [Recovery evidence pending](../evidence/g431-swdio-2026-10-05/README.md) |

The final two-motor setup used Mini 6.7 ID 1 and replacement FS75100 ID 2. A second Mini passed motor/Hall detection but did not appear on CAN after cable swaps/separate checks; its failure mechanism remains unestablished.

The [startup checks](../evidence/dual-startup-checks.txt) recorded 42 synthetic/pure logic checks, missing-link arming, duplicate IDs and malformed requests. The [powered idle log](../evidence/dual-links-idle.txt) recorded fresh approximately 50 Hz links and reported zero transmit errors while disarmed. The [tuned motor log](../evidence/dual-motor-tuned.jsonl) contains eight direction-request segments of at least 0.6 s reaching over 500 eRPM in the requested direction, with the session ending disarmed and stopped. These are sampled observations, not independently timed command-latency measurements.

For motor 2, records describe changing battery regeneration allowance from 0 to −0.5 A, then speed PID P/I from 0.004/0.004 to 0.01/0.008 while retaining +5/−2 A motor and +2 A battery discharge limits. These are specific bench settings, not reusable calibration. Approximately 1950–2050 eRPM was observed for a 2000-eRPM request; shaft-speed accuracy, loaded torque, position accuracy and settling time were not calibrated.

[Media](media-gallery.md) illustrate the setup; recording dates and synchronisation with telemetry are not established by supply filenames.

## Remaining validation

- G431 programmer verify log, exact flashed image/hash, UART output after reset, repaired-joint photograph and measured power-off continuity.
- Onboard G431 CAN, PWM and encoder functionality.
- 1 Mbit/s CANH/CANL edge capture, independent decoding, HSE-based timing and voltage/temperature tolerance.
- Actual multi-node harness with motor noise, cold starts, communication loss and independent wheel commands.
- Loaded low-speed control, four-wheel locomotion, slope/torque/thermal measurements and physical stop provisions.
- Host-side packet/control tests and CI for parsing, byte order, limits, stale feedback, arming/reversal and malformed input.

Five archived applications previously passed [offline builds](../evidence/build-checks.md). The 1 Mbit/s overlays were rebuilt offline for this publication and matched the tested binary hashes. Neither offline building nor archive preparation demonstrates new hardware operation. Licenses for the team's original material remain [unresolved](../THIRD_PARTY_NOTICES.md).
