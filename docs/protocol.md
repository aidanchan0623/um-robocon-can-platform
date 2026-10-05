# Protocol notes

## Historical MCU ping/reply — 250 kbit/s

The G474 sends an 11-bit standard-ID Classic CAN frame with ID `0x123`, DLC 1 and byte `0x55` every 500 ms. The F303 software recognises `0x123`, toggles PA5/LD2 and sends ID `0x124`, DLC 1, byte `0x55`. The G474 toggles its LED when it receives `0x124`.

CAN itself does not define these IDs as addresses or commands. This meaning comes from this application's code. `0x55` is a fixed demonstration payload, not a cryptographic check or an instruction inherently understood by STM32. The receiver currently checks the ID but does not validate this byte. LED toggling therefore demonstrates the exchange, **not exhaustive byte-level integrity or command accuracy**.

The G474 diagnostic `canQueued` counts successful enqueue calls. `canCompleted` counts observed/cleared completion flags and can coalesce events; it is not a perfect per-frame delivery counter. A CAN acknowledgement also means some active node accepted the frame at the CAN layer, not that a particular application executed it.

Timing:

- G474: 16 MHz / [2 × (1 + 25 + 6)] = 250 kbit/s.
- F303: 8 MHz / [2 × (1 + 13 + 2)] = 250 kbit/s.

## CAN1M integrity-test snapshot — 1 Mbit/s

This separate diagnostic application is built using the [source overlays and reproduction procedure](../evidence/can-1mbit-2026-10-05/REPRODUCTION.md). It does not replace the original 250 kbit/s folders or implement VESC/C620 commands. See [version/commit and image identities](firmware-provenance.md).

| Field | Request | Echo |
| --- | --- | --- |
| Standard 11-bit ID | `0x601` from G474 | `0x602` from F303 |
| Classic CAN data length | 8 bytes | Exact copy of all 8 request bytes |
| Bytes 0–3 | Big-endian sequence number | Same sequence |
| Bytes 4–7 | Rotating zero, one, 0x55, 0xAA, sequence-derived and mixed patterns | Same pattern |

G474 checks frame type, DLC, every payload byte and the sequence against its 64-entry outstanding window. Unknown/duplicate replies increment `unexpected`; a missing reply expires after 20 ms. Strict arrival ordering within the outstanding window is not enforced. F303 validates request framing and echoes bytes; full content validation happens on G474. The host pauses/drains traffic and reconciles six independent queued/RX/TX/echo totals before accepting a stage.

G474 nominal timing is 16 MHz / [1 × (1 + 11 + 4)] = 1 Mbit/s. F303 uses 32 MHz / [2 × (1 + 11 + 4)] = 1 Mbit/s. Both use a 75% sample point, 4-TQ SJW and internal HSI-derived clocks. The [verification page](verification.md) records achieved throughput, scheduling misses, DWT-based application round trip and clock/physical-layer limits.

`S` starts a fresh run and resets sequence/counters; `P` pauses new sends; `R` resets the test while paused; `1`/`2`/`3` select 100/1,000/2,500 requested pairs/s and require a subsequent start. These are synthetic diagnostic commands, not motor controls. The hardware runner performs MCU software resets and sends live commands; the offline builder/auditor does not.

## VESC application

VESC uses Classic CAN with 29-bit extended identifiers. This implementation uses:

```text
extended ID = (packet type << 8) | controller ID
```

| Operation | Packet type | Example for controller 1 |
| --- | --- | --- |
| SET_CURRENT | 1 | ID `0x00000101`, signed big-endian int32, current × 1000 |
| SET_RPM | 3 | ID `0x00000301`, signed big-endian int32 electrical RPM |
| STATUS 1 | 9 | ID `0x00000901`, 8-byte feedback |

For +1400 eRPM the four command bytes are `00 00 05 78`; for −1400 they are `FF FF FA 88`. Zero-current/coast is SET_CURRENT with `00 00 00 00`, not a claim of active braking.

STATUS 1 contains signed 32-bit eRPM, signed 16-bit current in 0.1 A units and signed 16-bit duty in 0.001 units, all big-endian. The firmware checks the extended frame type, packet type and DLC before decoding. Each controller has a distinct ID; the dual app tracks both feedback links.

The dual app sends separate packets to IDs 1 and 2. It currently requests the same eRPM from both; commands are neither atomic nor an independent four-wheel controller. Each ESC performs its own motor control.

For the specified 14-pole motor, seven pole pairs mean shaft RPM = eRPM / 7. An eRPM report is not a wheel encoder measurement and does not establish position accuracy or ground speed under slip.

Diagnostic `tx` counts accepted transmit queue entries, not remote execution. Fresh `rx1`/`rx2` and plausible speed feedback are stronger application-level observations but are not an exhaustive CAN reliability test. The separate CAN1M diagnostic now covers byte/sequence echo integrity on two external nodes; that result does not add those checks to the VESC motor application. Independent motor-frame decoding, loaded testing and measured bus utilisation remain future work.

References: [VESC CAN documentation](https://github.com/vedderb/bldc/blob/master/documentation/comm_can.md), [VESC firmware communication implementation](https://github.com/vedderb/bldc/blob/master/comm/comm_can.c) and the included `vesc_can.c`/`vesc_can.h` sources. Vendor firmware/version compatibility must be checked for the actual ESC; no VESC firmware replacement is supplied here.
