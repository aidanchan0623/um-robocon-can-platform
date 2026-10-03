# My tests and current limitations

## Historical milestones

Dates below are reconstructed from the CAN project discussion and the separate BLDC test records. They are test-history dates, not manufactured Git commit history.

| Stage | Record / observation | Scope |
| --- | --- | --- |
| 24 September 2026 | Programmer download-complete confirmation for custom STM32 work | Successful programming session, not full UART/CAN validation |
| Late September | G431 USART3 tests and scope/adapter investigation | UART bring-up attempted; clean terminal decoding not established by the selected archive |
| 27 September | G474 internal CAN loopback passed | Internal controller/configuration only |
| 30 September | G474/F303 normal-mode CAN success reported in the project discussion | MCU-to-MCU bench demonstration; selected video pending |
| Subsequent diagnosis | I traced pressure-sensitive TCAN3413 CAN lead solder contact and restored communication through rework | Physical assembly finding; does not resolve all separate SWD/UART issues |
| 1 October | One BLDC controlled over CAN with keyboard requests | Single-controller unloaded bench demonstration |
| 1 October | Replacement FS75100 ID 2 received alongside Mini ID 1 | Both feedback links approximately 50 Hz; see included telemetry |
| 1 October | Two motors operated, with FS75100 startup tuning | Mixed-ESC unloaded bench demonstration, not locomotion |

## Evidence included

- [dual-startup-checks.txt](../evidence/dual-startup-checks.txt): historical serial verification of the dual application with ESCs initially off. `test=42` covers synthetic/pure control and packet logic; missing-link arming, duplicate IDs and malformed requests were also exercised. This is not a powered two-motor test.
- [dual-links-idle.txt](../evidence/dual-links-idle.txt): historical powered, disarmed check with both feedback links rising and reported `tec=0`, `bo=0`. Outputs are zero; this proves reception, not rotation.
- [dual-motor-tuned.jsonl](../evidence/dual-motor-tuned.jsonl): historical keyboard/MCU feedback and separate ESC 2 USB snapshots during the tuned two-motor test. Serial counters, eRPM, state and timestamped samples are retained; private flash/probe identifiers are not included.
- Firmware source and EasyEDA exports: current collected snapshots, not exact binary provenance for every earlier test.
- [Media gallery](media-gallery.md): supplied bare-PCB and two-motor bench photographs, SWD debugging captures, a historical schematic image and a 20.8-second bench demonstration video. Supply dates do not establish recording dates or synchronisation with the telemetry logs.

Decoded CAN traces and before/after annotated CAN solder-repair captures are pending. The included scope photographs are SWCLK/SWDIO, not proof of byte-perfect UART or CAN decoding.

## Results and interpretation

I used Mini 6.7 ID 1 and FS75100 ID 2 for the final dual setup. A second Mini passed motor/Hall detection but did not appear on CAN, even after I swapped cables and checked it separately. Note: I have not established its fault mechanism; I replaced it for the successful dual test.

Motor 2 had intermittent starts. Historical records describe changing its battery regeneration allowance from 0 to −0.5 A, then speed PID P/I from 0.004/0.004 to 0.01/0.008 while retaining +5/−2 A motor and +2 A battery discharge limits. Settings were read back after restart. These are specific bench settings, not reusable calibration for other motors or robot loads.

The tuned log contains eight direction-request segments lasting at least 0.6 s that reached over 500 eRPM in the requested direction. Note: I used snapshots and sampled feedback to observe the motor responses. I still need independently timed CAN captures to measure packet latency. The recorded test ended disarmed with both motors stopped.

I observed roughly 1950–2050 eRPM after requesting 2000 eRPM on the bench. Note: I read that value from the controller’s electrical-speed feedback. I have not calibrated shaft-speed accuracy or measured loaded torque, position accuracy or settling time.

## What I still need to validate

- Precise payload verification through an independent CAN analyser or sequence-number stress test.
- Continuous reliability, bit-error rate, worst-case latency, EMC or fault-injection coverage.
- Actual endpoint resistor values on the final mixed-ESC bench arrangement.
- Onboard G431 CAN operation or resolution of every G431 SWD/UART failure.
- Functional validation of the board's PWM and encoder interfaces.
- Four ESCs, independent wheel commands, loaded locomotion, slope climbing or 2.5 N·m wheel torque.
- Safety certification, instant braking/reversal, or a physical emergency-stop implementation.

## Repository preparation checks

Five copied firmware snapshots are built offline using the supplied builder and STM32 GCC. Build results are recorded in [build-checks.md](../evidence/build-checks.md). No connected MCU, serial terminal, ESC configuration or motor operation is touched during this packaging work.

Only the selected project files and team-supplied media are included. Generated firmware binaries, complete flash backups, private probe identifiers, unrelated project files and per-motor calibration backups are excluded. The demonstration video retains its original audio and includes the laptop control interface and background troubleshooting discussion; it is not a sanitised screen recording. Original source workspaces and supplied media are preserved.

## My next software tests

I plan to add a standalone automated test suite. My current evidence includes startup self-checks and successful offline builds, which cover a narrower scope.

Planned coverage includes packet byte order and lengths, command parsing and limits, stale-feedback/host timeouts, arming and reversal states, and malformed input. Host-side tests can exercise pure logic without powering motors; independent CAN captures and sequence tests are still needed to verify the physical link. CI integration will follow when those tests are added.
