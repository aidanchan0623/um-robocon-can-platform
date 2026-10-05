# Assembly and bring-up checklist

Two separate faults involved fine-pitch lead-to-pad contact: the TCAN3413 CAN leads and, subsequently, the G431 SWDIO lead. The corrective process is to verify every assembled fine-pitch connection against the schematic before bring-up, with recorded results rather than visual inspection alone. See [both incidents](debugging.md).

## With all power removed

Disconnect battery, bench supply, USB, ST-LINK and UART adapter. Confirm the rails have discharged before using resistance/continuity mode. Use magnification and fine insulated tips; avoid bending leads or bridging neighbouring pins.

1. Check component orientation, pin 1, missing joints, solder bridges and regulator/transceiver/MCU placement against the [source exports](../hardware/source).
2. For **every populated fine-pitch IC lead**, inspect the lead-to-pad joint and measure to an accessible point on its intended net. Probe the lead itself where practical, not only its pad. Record open/unconnected pins as such. A continuity beep is insufficient where a series resistor is fitted; record resistance and the expected path.
3. Check adjacent pins for unintended bridges against the schematic. Some neighbouring pins intentionally share supply/ground nets, and semiconductor paths can affect in-circuit readings; do not require infinite resistance indiscriminately.
4. Verify each MCU supply and ground connection, regulator paths, reset, boot straps, SWD, UART and transceiver signals. Check rail-to-ground resistance for an unexpected low-resistance short; account for charging capacitors and other parallel paths.
5. Repeat questionable readings with light, consistent probe contact. Results that depend on pressing the package/lead or moving a connector fail this check. Inspect/rework and repeat before applying power.
6. Photograph repaired joints and record the measured path, meter reading, expected resistance and date. Recheck nearby pins after rework.

| Critical path on this revision | Expected check |
| --- | --- |
| DEBUG DIO to G431 PA13, pin 49 | Approximately 33 ohms through R5, stable; latest repair reading still pending |
| DEBUG CLK to G431 PA14, pin 50 | Approximately 33 ohms through R6, stable |
| DEBUG reset to G431 NRST, pin 7 | Approximately 100 ohms through R8; account for the reset pull-up/capacitor |
| UART header RX label to G431 PC10 TX | Verify through R3 using the fitted value and adapter-oriented header mapping |
| EX_MCU_CAN TX to TCAN3413 TXD, pin 1 | Verify intended net continuity and isolation from competing MCU outputs |
| EX_MCU_CAN RX to TCAN3413 RXD, pin 4 | Verify intended net continuity |
| TCAN3413 CANH pin 7 / CANL pin 6 to bus connectors | Verify each separate signal path, including its own CMC winding or 0-ohm bypass |
| CANH to CANL across the unpowered complete bus | About 62 ohms for two fitted 124-ohm board endpoints; about 60 ohms for two 120-ohm endpoints |

These expectations come from the documented schematic, not new measurements of a repaired board. Unexpected readings need path tracing; in-circuit parallel paths can affect the result.

## Powered bring-up, one interface at a time

Start with a current-limited supply and disconnected motor power. Measure the rails directly at IC supply pins and confirm reset/standby levels. Connect only one verified supply arrangement; debug target-voltage sensing does not replace the board's power supply.

- Confirm the exact MCU identity through SWD; save the programmer log, firmware SHA-256 and explicit verify result.
- Reset and capture UART output using the documented baud rate and a 3.3 V logic adapter; save a timestamped capture.
- Test internal CAN loopback separately, then normal-mode external communication with independent endpoint checks.
- Save a CANH/CANL waveform with probe attenuation, scales, trigger, bit rate and measurement points recorded. Scope ground clips go only to the verified common circuit ground.
- Extend to PWM/encoder tests and motor operation only after recording the relevant interface checks.

## Next PCB revision

Provide accessible, clearly labelled test points for **CANH, CANL, TXD, RXD, SWCLK, SWDIO, NRST, 3.3 V and GND** where v1 lacks suitable access. Include nearby ground points for short scope connections, explicit MCU-direction UART labels, and a documented means of isolating onboard MCU outputs during external-controller tests. Review added CAN test-point geometry for stubs rather than attaching long branches.

Keep a board-by-board bring-up record. Two solder incidents justify this process improvement; they do not establish that every previous failure had the same cause.
