# Build and use

## Choose the correct target

The G431 onboard MCU, G474 Nucleo and F303 Nucleo are different targets. Never flash one target's binary onto another. This archive preserves five independent source snapshots rather than a single application supporting every board.

## Build without hardware

Use STM32CubeIDE's **Import → Existing Projects into Workspace**. Import the application folder containing `.project`; for the F303 import its `STM32CubeIDE` subfolder instead. It uses relative linked resources to `Src`, `Inc` and `Drivers` one level above. Select the intended project and build. The original project names are retained inside the IDE.

Alternatively, from the repository root in PowerShell:

```powershell
.\tools\build.ps1 -Project g474-can-ping -ToolBin 'D:\your-toolchain\bin'
.\tools\build.ps1 -Project f303-can-reply -ToolBin 'D:\your-toolchain\bin'
```

Use the actual directory containing `arm-none-eabi-gcc.exe`, `arm-none-eabi-objcopy.exe` and `arm-none-eabi-size.exe` from your STM32 toolchain. If GCC is already on PATH, omit `-ToolBin`. The other project names are `g431-uart`, `g474-vesc-single` and `g474-vesc-dual`.

The offline builder targets Cortex-M4/hard-float, uses `-Wall -Wextra -Werror`, and writes ELF/HEX/BIN into each application's ignored `Build` directory. The F303's vendored ST EXTI source has two unused `Edge` arguments; unused-parameter warnings are suppressed for that file only, without changing the vendor source. It never invokes a programmer or opens a serial port. Vendored HAL/CMSIS files are included so the build does not fetch dependencies.

Open the `.ioc` in CubeMX to inspect pin/clock configuration. These are historical working snapshots; check regeneration diffs before flashing. Preserve separate application files and USER CODE sections. Some manually implemented GPIO details are in those sections. Do not assume regenerated output is identical to the archived tested firmware.

## Program deliberately

1. Disconnect motor power for an MCU-only flash/check. Identify the target and connect its correct SWD/ST-LINK interface. A Nucleo is normally programmed through its built-in ST-LINK USB connection; the custom G431 needs its external debug wiring.
2. In STM32CubeProgrammer choose ST-LINK/SWD and Connect. Confirm the MCU family/device identity before proceeding.
3. Open the newly built ELF for **that target**, enable verification, download and wait for explicit successful verification.
4. Disconnect the programmer and reset/run the application. A build-success message alone does not prove programming or execution.

No automatic flash script or private probe serial number is included. No hardware was reflashed during preparation of this repository.

## G474–F303 CAN test

With power removed, wire each PA12 TX to its own transceiver's TXD and PA11 RX to RXD, plus common ground. Isolate the onboard custom-board MCU. Power each custom board separately through its documented power input. Connect H→H and L→L with a twisted pair and terminate only the two cable ends. See [hardware notes](../hardware/README.md) for this board's split-resistor values and CMC bypasses.

Flash `g474-can-ping` to the G474 and `f303-can-reply` to the F303. Both archived applications use normal Classic CAN at 250 kbit/s. In normal operation the G474 sends every 500 ms; F303 LD2 toggles on a recognised ping and G474 LD2 toggles on a recognised reply. The archived F303 snapshot has **no independent startup-blink test**; a dark LED alone does not establish whether code is executing.

For an internal-loopback diagnostic on the G474 only, make a separate local test build: change `FDCAN_MODE_NORMAL` to `FDCAN_MODE_INTERNAL_LOOPBACK` and the node-A received-ID check from `0x124` to `0x123`. Its LED then responds to its own frames. Restore both lines and reflash normal mode before testing the external bus. Loopback does not test physical pins, solder or the transceiver.

## G431 UART snapshot

The [5 October SWDIO repair](debugging.md#case-2-g431-swdio-contact-and-programming-access) has operator-reported flash success; its exact flashed image, verify log and UART capture are pending. The archived UART application below is not asserted to be that repaired board's current image.

This snapshot sends `STM32 UART OK\r\n` through USART3 PC10 TX, **9600 baud, 8N1**, repeatedly with a 500 ms delay. PC11 is RX. Use a 3.3 V logic UART adapter RX connected to MCU TX and a shared ground. Do not connect an unverified adapter TX voltage or parallel adapter and board supplies.

The physical UART header label is adapter-oriented; consult [hardware notes](../hardware/README.md), not just the word TX. An idle TX line should be high, with logic-level transitions during each burst. At 9600 baud a bit lasts about 104 µs; approximately 100 µs/div is useful for individual bits and 2–5 ms/div for the roughly 16 ms message. Use DC coupling, matched 10× probe settings, 1 V/div and a falling-edge trigger around 1.5 V. Ground the probe to a verified circuit ground. This describes expected behavior, not a claim that the historical UART terminal test was fully validated.

## VESC bench control

Prepare each ESC for its own motor through compatible VESC Tool: appropriate motor detection, unique IDs, VESC CAN mode, 250 kbit/s, Status 1 at about 50 Hz, suitable battery/current limits, and a 300 ms communication timeout with zero timeout brake current for the coast tests. Keep manufacturer-compatible firmware; this repository does not flash the ESCs. Never reuse another motor's detection/calibration values.

The successful final dual hardware was ID 1 Mini 6.7 (sensorless) and ID 2 FS75100 (Hall-configured), on 4S. Those bench settings are observations, not universal motor recommendations. Regeneration needs a suitable energy-absorbing power source; an ordinary bench supply may not absorb returned energy.

After independently verifying wiring, termination and ESC settings, program the chosen G474 VESC application. Connect through the Nucleo ST-LINK virtual COM port at 115200 baud; this firmware uses LPUART1 PA2/PA3. Launch that folder's `Start-Keyboard-Control.cmd`, choose the actual port/IDs, click Connect and verify fresh feedback. The launcher does not hard-code a user's COM port or auto-arm.

Secure motors with shafts clear, prepare a physical motor-power stop, release arrow keys and click Arm. Up/Down requests positive/negative eRPM; release, Space/Esc or STOP removes drive torque/disarms as implemented. **Coast is not a brake or position hold.** The dual app commands the same signed speed to both; motor orientation may differ.

Host silence beyond 250 ms, stale feedback beyond 300 ms, malformed commands and reported CAN failures disarm the software and attempt zero-current commands. A failed CAN link can prevent a stop message being delivered, so the ESC timeout and physical power stop are essential. Reversal waits until reported speed is within ±350 eRPM before ramping the opposite direction; this is not instant reversal at arbitrary load.

No motors were run during repository preparation. Existing test logs are historical bench evidence, not a certification of safe robot operation.
