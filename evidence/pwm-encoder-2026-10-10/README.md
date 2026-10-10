# PWM and encoder evidence — 10 October 2026

See [the milestone report](../../docs/pwm-encoder-bringup.md) for interpretation. This archive separates recorded short CAN checks from later video observations; it does not extend the earlier external-Nucleo endurance result to the onboard G431.

## Original media

| File | Supplied filename | SHA256 |
| --- | --- | --- |
| [Video 1](motor-encoder-demo-01-original.mp4) | WhatsApp Video 2026-10-10 at 2.24.37 PM.mp4 | `DAE009D11C5B318281A0DCD7A5835F7607B941FF1857CA665D173A22B9A2344B` |
| [Video 2](motor-encoder-demo-02-original.mp4) | WhatsApp Video 2026-10-10 at 2.24.43 PM.mp4 | `3314D1E4ED4CAD38BA901E855E6C3140200F4EB15732459F0A2F9CC810BD5426` |
| [Original photo](bench-setup-original.jpg) | Supplied clipboard photograph | `AD3D41C2FDD12957D8FC7264566D9D879C7C8F1375A47C7CEECA9757D92257C9` |

The copies match the supplied original bytes. Filenames are not independent timestamp evidence. Audio remains included; public release is subject to the owner's media/privacy review.

[Annotated photo](bench-setup-annotated-v2.png) is a descriptive AI-assisted derivative. [Initial prompts](annotation-prompts.md) and [revision prompt](annotation-v2-prompt.md) disclose how it was made. The user clarified that the lower PCB is a CANDrive board used as an external transceiver without its local MCU.

## Saved diagnostic records

- [Paired F303/G431 inspection](records/paired-link-1mbit.json): includes startup observations, not just the successful final state.
- [Stopped 35-second link check](records/stopped-link-1mbit.json): 288 samples, first/last counters and build metadata; this was not a powered motor test.
- [Independent G431 runtime/register read](records/g431-runtime-1mbit.json): final stopped state and CAN error diagnostics.
- [Earlier encoder diagnostics](records/earlier-encoder-diagnostics.json): poor directional counts before the later video demonstration. Do not treat this file as the log of the successful video.

Diagnostic JSON files are copied unmodified; they contain local build paths and hardware metadata. Publication preparation did not generate new CAN traffic or command the motor.

## Source review and offline tests

[Source appendix](source-snapshot/README.md) contains the host panel, tests, principal endpoint sources and the original build scripts. [Offline test output](source-snapshot/offline-test-results.txt) records 26 passing mocked-host tests rerun from the copied snapshot.

[SHA256 manifest](manifest.json) identifies these archived bytes. These are publication-time source identities, **not proof of the flash-time image used in the videos**. No release/tag or new hardware result is implied.
