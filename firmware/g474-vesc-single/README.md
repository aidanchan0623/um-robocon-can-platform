# One-VESC G474 bench application

Target: NUCLEO-G474RE. FDCAN1 PA11 RX / PA12 TX at 250 kbit/s; LPUART1 PA2/PA3 through the ST-LINK virtual COM port at 115200 baud. Default ESC ID 1. Original IDE project name: `G474_VESC_CAN`.

The keyboard launcher requires port selection, Connect and manual Arm. Up/Down requests signed electrical RPM; release removes torque with zero current. This is coast, not active braking. Firmware starts disarmed and checks host/feedback freshness. The startup `test=25` result denotes pure control/packet checks, not physical motor experiments.

See [build/use](../../docs/build-and-use.md), [protocol](../../docs/protocol.md) and [verification limits](../../docs/verification.md). Never run before checking motor configuration, power, termination and a physical motor-power stop. No automatic flash utility or private full-flash backup is included.
