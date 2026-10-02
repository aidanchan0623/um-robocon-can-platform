# G431 UART bring-up snapshot

Target: custom STM32G431RBT6. USART3 PC10 TX / PC11 RX, 9600 baud, 8N1. Repeats `STM32 UART OK\r\n` with a 500 ms delay. The retained project name is `CAN_TEST`, but this snapshot is a UART test, not a CAN application.

Historical terminal decoding and later SWD failures remain unverified/unresolved here. See [build/use](../../docs/build-and-use.md) and [header naming](../../hardware/README.md).
