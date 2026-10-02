# Protocol notes

## MCU ping/reply

The G474 sends an 11-bit standard-ID Classic CAN frame with ID `0x123`, DLC 1 and byte `0x55` every 500 ms. The F303 software recognises `0x123`, toggles PA5/LD2 and sends ID `0x124`, DLC 1, byte `0x55`. The G474 toggles its LED when it receives `0x124`.

CAN itself does not define these IDs as addresses or commands. This meaning comes from this application's code. `0x55` is a fixed demonstration payload, not a cryptographic check or an instruction inherently understood by STM32. The receiver currently checks the ID but does not validate this byte. LED toggling therefore demonstrates the exchange, **not exhaustive byte-level integrity or command accuracy**.

The G474 diagnostic `canQueued` counts successful enqueue calls. `canCompleted` counts observed/cleared completion flags and can coalesce events; it is not a perfect per-frame delivery counter. A CAN acknowledgement also means some active node accepted the frame at the CAN layer, not that a particular application executed it.

Timing:

- G474: 16 MHz / [2 × (1 + 25 + 6)] = 250 kbit/s.
- F303: 8 MHz / [2 × (1 + 13 + 2)] = 250 kbit/s.

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

Diagnostic `tx` counts accepted transmit queue entries, not remote execution. Fresh `rx1`/`rx2` and plausible speed feedback are stronger application-level observations but are not an exhaustive CAN reliability test. Sequence counters, commanded-versus-measured logging, frame decoding, loaded testing and bus utilisation measurements remain future work.

References: [VESC CAN documentation](https://github.com/vedderb/bldc/blob/master/documentation/comm_can.md), [VESC firmware communication implementation](https://github.com/vedderb/bldc/blob/master/comm/comm_can.c) and the included `vesc_can.c`/`vesc_can.h` sources. Vendor firmware/version compatibility must be checked for the actual ESC; no VESC firmware replacement is supplied here.
