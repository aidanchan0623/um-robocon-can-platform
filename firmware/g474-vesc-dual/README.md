# Two-VESC G474 bench application

Target: NUCLEO-G474RE. FDCAN1 PA11 RX / PA12 TX at 250 kbit/s; ST-LINK virtual serial at 115200 baud. Default ESC IDs 1 and 2. Original IDE project name: `G474_DUAL_VESC_CAN`.

The final demonstrated hardware was a Mini 6.7 and replacement FS75100, each with a 6374 motor. Both feedback links must be fresh and both reported speeds within ±350 eRPM before manual arming. Host expiry is 250 ms and feedback expiry 300 ms. The paired app commands the same requested eRPM using **two separate CAN packets**; this is not an independent four-wheel controller.

Key release requests zero current/coast. Direction reversal waits for the stopped threshold before ramping. CAN failure can prevent stop delivery, so each ESC needs its own timeout and the setup needs a physical motor-power stop. The startup `test=42` denotes logic checks, not 42 physical motor tests.

See [build/use](../../docs/build-and-use.md), [protocol](../../docs/protocol.md) and [historical evidence](../../docs/verification.md). No automatic flash utility, probe-specific setting or full-flash backup is included.
