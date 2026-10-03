# Evidence

I included three telemetry files from our 1 October 2026 bench tests. I did not run new experiments while assembling this archive. See [verification](../docs/verification.md) for interpretation and limitations. Motor JSONL timestamps are UTC; firmware `ms` values are tick counts since MCU boot.

Firmware `tx` means enqueue success, `tec` is the reported transmit error count and `bo` indicates reported bus-off state. Neither a zero error count nor activity on a scope is a lifetime reliability guarantee.

The [media gallery](../docs/media-gallery.md) contains team-supplied PCB/bench photos, two SWCLK/SWDIO captures and a [bench demonstration video](videos/bench-demo-supplied-2026-10-02.mp4). Note: I added the media on 2 October, but I have not established that it matches the 1 October telemetry session. My scope images cover SWD. I use the video to show the bench workflow and still need independent CAN decoding and speed measurements.

Note: I still need to capture decoded CAN traces and annotated before/after measurements of the solder repair. The current archive contains only the measurements and media I have available.
