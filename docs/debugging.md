# Hardware debugging case studies

Two distinct lead-to-pad solder faults motivated the [assembly and bring-up checklist](assembly-checklist.md). The first restored external CAN communication; the second concerns programming access to the onboard G431. Evidence strength differs between the two cases.

## Case 1: intermittent TCAN3413 CAN signal path

## Problem

The intended G474–F303 setup had one powered custom transceiver board per Nucleo, TX/RX connections to the external-MCU headers, a shared ground and a twisted CANH/CANL pair. The onboard custom-board MCUs were disconnected. Initially, firmware could be built/programmed but communication did not reliably work.

The investigation separated several questions that had initially been conflated:

1. Was the STM32 programmed and executing?
2. Did its CAN controller work internally?
3. Did its physical TX/RX signals reach the transceiver?
4. Did the transceiver connect to a properly terminated external bus?
5. Did the other controller actually receive and reply?

## What I observed

| Observation | What it established | What it did not establish |
| --- | --- | --- |
| Programmer reported download complete | Firmware write completed in that session | Application behavior or CAN connectivity |
| G474 queued frames without completed transmission | Code reached CAN enqueue | Receiver acknowledgement or correct external signal path |
| Internal G474 loopback passed | Controller/configuration worked in loopback | PA11/PA12, transceiver, bus wiring or solder contacts |
| Power LEDs and supply measurements | Some power was present at measured points | Every IC supply pin and ground connection was sound |
| Bus resistance sometimes near 60 Ω | A termination path existed at that moment | Reliable lead-to-pad contact or correct waveforms |
| Resistance varied with probe pressure, approximately 32 kΩ versus 60 Ω | An intermittent physical connection was strongly suspected | Which individual joint was faulty without tracing/rework |
| Scope results were inconsistent; I traced poor TCAN3413 CAN lead contact | I located the assembly fault through probing and rework | A complete quantitative signal-integrity qualification |
| CAN worked after solder rework | Communication resumed after my solder rework | All prior UART/SWD faults had the same cause |

I reconstructed this sequence from my debugging notes, project discussion and firmware/test records. Note: I have not included annotated before/after captures or recorded which joint I repaired first. The resistance values are my original bench observations; I did not repeat those measurements while preparing this page.

## Root cause

The TCAN3413 CANH/CANL leads were not reliably soldered to their respective pads. Probe pressure sometimes changed the apparent continuity. After I repaired these contacts, the CAN setup worked.

**CANH and CANL must not be soldered together.** The failure was inadequate lead-to-pad contact, not a missing H-to-L solder bridge.

## Why the early checks were misleading

Termination sits on the connector-side bus. A plausible H-to-L resistance can therefore coexist with an open or intermittent connection between that bus and the transceiver. Similarly, internal loopback deliberately bypasses external hardware. Passing one layer of the system cannot validate the next layer.

A DMM reports an average of a switching signal; it cannot prove a UART/CAN bit stream is correct. Oscilloscope scale, trigger, probe attenuation and a reliable short ground connection all matter. Ground clips on an ordinary bench scope share protective earth: connect them only to a verified common circuit ground, never to CANH/CANL or a positive supply.

## Follow-up practice

- With all power removed, inspect/rework contacts and check continuity from the actual IC lead to the connector; do not rely only on pad-to-pad continuity.
- Check that nearby leads are not shorted and readings remain stable without pressing on the joint.
- Verify VCC/VIO/STB directly at the transceiver, then test normal-mode TXD, bus differential activity and RXD.
- Keep hardware, software and measurement-setting changes separate and record each result.
- Preserve annotated captures and decoded frames, not just a photograph showing activity.

## Case 2: G431 SWDIO contact and programming access

On 5 October, my custom G431 board failed to connect through ST-LINK while its previously flashed UART firmware could still execute. Changing connection/reset settings did not establish communication. A steady debug-line voltage was inconclusive: a meter cannot show a short SWD transaction.

I captured SWCLK at the MCU pin during a connection attempt, observing clear switching and a displayed frequency near 96 kHz for the nominal 100 kHz setting. This located the programmer's clock at the measurement point, but it did not show that the MCU returned a valid SWD response.

I subsequently found that the **SWDIO lead was not properly soldered**, addressed the connection and reported successful flashing. This strongly supports a physical SWDIO contact fault as the cause of this failure. It does not establish the cause of every earlier programming problem or permanent MCU damage.

| Observation | Interpretation | Evidence status |
| --- | --- | --- |
| Existing UART firmware still ran | CPU could execute that image; debug connectivity remained unresolved | Operator observation |
| SWCLK switched at the MCU pin | Clock reached that point; target response was not established | Supplied scope observation, no decoded transaction |
| Inadequate SWDIO solder joint found | A physical fault existed on the bidirectional debug-data path | Operator diagnosis; joint photo pending |
| Successful flash reported after repair | Programming access reportedly recovered | Verify log and exact image hash pending |
| Approximately 33-ohm DIO-to-PA13 expectation | R5 is a 33-ohm series resistor in the reviewed schematic | Expected value; post-repair reading pending |

The board was disconnected during this documentation update. I have not added a new programmer verify log, UART capture after reset, repair photograph or continuity measurement. The [recovery evidence register](../evidence/g431-swdio-2026-10-05/README.md) keeps those gaps explicit. Successful flashing alone also does not validate onboard CAN, PWM or encoder functions.

### Process lesson

Clock activity and running old firmware were useful clues, but neither verified the complete debug path. Check fine-pitch **lead-to-net continuity**, account for series resistors and repeat measurements without pressing on a questionable joint. Record both SWCLK and SWDIO paths, then save programmer verification and application output after repair. The earlier CAN solder fault and this SWDIO fault are separate findings that justify a repeatable assembly procedure.
