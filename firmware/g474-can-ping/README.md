# G474 CAN ping snapshot

Target: NUCLEO-G474RE. PA12 TX, PA11 RX, PA5 LD2. Normal-mode Classic CAN, 250 kbit/s, standard ID `0x123` and payload `55` every 500 ms. LED toggles on reply ID `0x124`; `NODE_A=1` selects the sender. Requires an external powered transceiver.

The `canQueued` counter is enqueue success, not delivery. Completion flags can coalesce; see [protocol](../../docs/protocol.md). Internal-loopback instructions and flashing cautions are in [build/use](../../docs/build-and-use.md). Original IDE project name: `can2_test`.
