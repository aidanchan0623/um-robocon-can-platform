# F303 CAN reply snapshot

Target: NUCLEO-F303RE. PA12 TX, PA11 RX, PA5 LD2. bxCAN normal mode at 250 kbit/s. Recognised standard-ID `0x123` frames toggle LD2 and produce `0x124`, DLC 1, payload `55`. The code does not validate the received payload byte.

Import the `STM32CubeIDE` subfolder; its relative links refer to `Src`, `Inc` and `Drivers` above it. Original project name: `F303_G474_CAN_B`. Requires its own powered transceiver. See [build/use](../../docs/build-and-use.md).
