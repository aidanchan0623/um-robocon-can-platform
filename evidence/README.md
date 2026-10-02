# Evidence

The three telemetry files are copied historical bench records from 1 October 2026, not new experiments. See [verification](../docs/verification.md) for interpretation and limitations. Motor JSONL timestamps are UTC; firmware `ms` values are tick counts since MCU boot.

Firmware `tx` means enqueue success, `tec` is the reported transmit error count and `bo` indicates reported bus-off state. Neither a zero error count nor activity on a scope is a lifetime reliability guarantee.

The [media gallery](../docs/media-gallery.md) contains team-supplied PCB/bench photos, two SWCLK/SWDIO captures and a [bench demonstration video](videos/bench-demo-supplied-2026-10-02.mp4). Media supplied on 2 October is not established to be from the same session as the 1 October telemetry. The scope images show the debug interface, not CAN traffic; the video is qualitative, not an independent payload or speed-accuracy test.

Decoded CAN traces and annotated before/after CAN solder-repair measurements are still pending. No missing media is replaced with invented measurements or demonstration claims.
