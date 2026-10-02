# Offline build checks — 2 October 2026

All five collected source snapshots compiled and linked using STM32 GNU Tools GCC 14.3 and `tools/build.ps1`, without connecting to hardware or downloading dependencies.

| Application | Text bytes | Data bytes | BSS bytes | Result |
| --- | ---: | ---: | ---: | --- |
| g431-uart | 8212 | 28 | 1716 | Pass |
| g474-can-ping | 7140 | 12 | 1684 | Pass |
| f303-can-reply | 5720 | 12 | 1612 | Pass |
| g474-vesc-single | 20212 | 96 | 2552 | Pass |
| g474-vesc-dual | 21616 | 100 | 2844 | Pass |

Build settings: Cortex-M4, Thumb, FPv4-SP-D16 hard-float, GNU C11, `-Og`, `-Wall -Wextra -Werror`, section garbage collection and newlib nano/nosys.

The F303 build selects the same HAL sources as its IDE project, excluding optional HAL timebase templates. Two unused `Edge` parameters in ST's EXTI implementation require `-Wno-unused-parameter` for that vendor file only. Application sources and third-party source text were not changed to make the builds pass. Earlier attempts to build every optional F3 driver/template exposed this build-selection issue; it is not evidence of a CAN application failure.

ELF/HEX/BIN and objects are local generated files and are excluded from Git. These checks prove source compilation/linking, not execution or new physical validation. Historical flash/runtime evidence is discussed separately in [verification](../docs/verification.md).
