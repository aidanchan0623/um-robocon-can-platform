# Debugging an intermittent CAN signal path

## Problem

The intended G474–F303 setup had one powered custom transceiver board per Nucleo, TX/RX connections to the external-MCU headers, a shared ground and a twisted CANH/CANL pair. The onboard custom-board MCUs were disconnected. Initially, firmware could be built/programmed but communication did not reliably work.

The investigation separated several questions that had initially been conflated:

1. Was the STM32 programmed and executing?
2. Did its CAN controller work internally?
3. Did its physical TX/RX signals reach the transceiver?
4. Did the transceiver connect to a properly terminated external bus?
5. Did the other controller actually receive and reply?

## Evidence and interpretation

| Observation | What it established | What it did not establish |
| --- | --- | --- |
| Programmer reported download complete | Firmware write completed in that session | Application behavior or CAN connectivity |
| G474 queued frames without completed transmission | Code reached CAN enqueue | Receiver acknowledgement or correct external signal path |
| Internal G474 loopback passed | Controller/configuration worked in loopback | PA11/PA12, transceiver, bus wiring or solder contacts |
| Power LEDs and supply measurements | Some power was present at measured points | Every IC supply pin and ground connection was sound |
| Bus resistance sometimes near 60 Ω | A termination path existed at that moment | Reliable lead-to-pad contact or correct waveforms |
| Resistance varied with probe pressure, approximately 32 kΩ versus 60 Ω | An intermittent physical connection was strongly suspected | Which individual joint was faulty without tracing/rework |
| Scope results were inconsistent; team identified poor TCAN3413 CAN lead contact | Physical investigation located the reported assembly fault | A complete quantitative signal-integrity qualification |
| CAN worked after solder rework | User-reported repair outcome supported the diagnosis | All prior UART/SWD faults had the same cause |

These observations are reconstructed from the project discussion, firmware/test records and Aidan's final diagnosis. The exact joint repaired first and annotated before/after scope captures are not yet included. The two resistance numbers are user-reported measurements, not new measurements made for this repository.

## Root cause

The TCAN3413 CANH/CANL leads were not reliably soldered to their respective pads. Probe pressure sometimes changed the apparent continuity. Aidan reports that after repairing these contacts, the CAN setup worked.

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

The separate G431 UART and intermittent SWD programming difficulties remain separate investigations. This CAN repair does not prove whether any MCU was damaged or explain every fault in the project's history.
