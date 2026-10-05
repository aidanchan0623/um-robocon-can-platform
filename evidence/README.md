# Evidence

The archive contains motor telemetry from 1 October and separate 1 Mbit/s CAN records from 5 October. No new hardware experiment was run while preparing this publication update. See [verification](../docs/verification.md) and [source provenance](../docs/firmware-provenance.md) for interpretation and limitations. Motor JSONL timestamps are UTC; firmware `ms` values are tick counts since MCU boot.

| Evidence | Scope |
| --- | --- |
| [Initial 1 Mbit/s stages](can-1mbit-2026-10-05/README.md) | Three stages, raw serial/CSV/SWD, JSON, firmware overlays and runner |
| [Extended 1 Mbit/s suite](can-1mbit-endurance-2026-10-05/README.md) | Twelve functionality stages plus a 30-minute soak, raw records and runner |
| [Aggregate result](can-validation-2026-10-05.json) | 5,330,951 pairs across both datasets; provenance and limits |
| [G431 recovery register](g431-swdio-2026-10-05/README.md) | Operator-reported SWDIO repair/flash success; further evidence pending |

Run `./tools/audit-can-evidence.ps1` from the repository root to repeat the offline raw-record reconciliation. These results use external Nucleos; they do not validate the onboard G431 CAN path.

Firmware `tx` means enqueue success, `tec` is the reported transmit error count and `bo` indicates reported bus-off state. Neither a zero error count nor activity on a scope is a lifetime reliability guarantee.

The [media gallery](../docs/media-gallery.md) contains team-supplied PCB/bench photos, two SWCLK/SWDIO captures and a [bench demonstration video](videos/bench-demo-supplied-2026-10-02.mp4). Note: I added the media on 2 October, but I have not established that it matches the 1 October telemetry session. My scope images cover SWD. I use the video to show the bench workflow and still need independent CAN decoding and speed measurements.

Note: I still need to capture decoded CAN traces and annotated before/after measurements of the solder repair. The current archive contains only the measurements and media I have available.
