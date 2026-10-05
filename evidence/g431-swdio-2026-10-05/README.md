# G431 SWDIO repair — evidence status

On 5 October 2026, Aidan reported finding an inadequately soldered SWDIO lead on the custom STM32G431RBT6 board and subsequently reported successful flashing. A supplied scope observation showed SWCLK activity at the MCU during a connection attempt. This supports the proposed diagnosis but does not replace a programmer verify log or functional UART capture.

The repaired board was disconnected when this publication update was prepared. No new verification, reset, flashing or UART acquisition was performed for the update. The exact image used for the reported successful flash was not identified.

| Recovery evidence | Status |
| --- | --- |
| SWDIO solder fault identified by operator | Reported |
| Successful flash after addressing the joint | Reported |
| Target identity and programmer verification log | Pending |
| Exact flashed image and SHA-256 | Pending |
| UART output captured after reset | Pending |
| Close-up of the repaired SWDIO joint | Pending |
| Power-off DEBUG DIO to PA13 resistance | Pending; approximately 33 ohms expected through R5 |

The expected resistance is a schematic-derived value, not an observed post-repair reading. The existing [SWD gallery](../../docs/media-gallery.md) contains earlier debug waveforms; those photographs are not labelled as evidence of this repair. No MCU-damage diagnosis or full-board functional pass is claimed.

See [case 2](../../docs/debugging.md#case-2-g431-swdio-contact-and-programming-access) and the [assembly procedure](../../docs/assembly-checklist.md). Add actual logs, joint photos and measurements here when they are available; preserve failures and record the exact firmware rather than replacing a reported observation with an unsupported confirmed pass.
