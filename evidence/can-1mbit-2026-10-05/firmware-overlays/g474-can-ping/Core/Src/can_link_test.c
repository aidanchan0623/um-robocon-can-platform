/* Bench-only sequence/echo test. No VESC or C620 motor commands. */
#include "can_link_test.h"
#include <stdio.h>
#include <string.h>

#define REQUEST_ID 0x601U
#define RESPONSE_ID 0x602U
#define WINDOW 64U
#define TIMEOUT_MS 20U
#define U(x) ((unsigned long)(x))

typedef struct {
    uint32_t magic, running, fault, rate, queued, completed, replies;
    uint32_t bad_bytes, unexpected, timeouts, queue_fail, rx_lost, tx_event_lost;
    uint32_t protocol_events, bus_off_events, tec, rec, max_tec, max_rec;
    uint32_t last_error, pending, max_rtt_us, late_sends, uart_errors;
} TestStats;
volatile TestStats canTest;
typedef struct { uint32_t seq, cycles, ms; uint8_t active; } Pending;
static Pending pending[WINDOW];
static FDCAN_HandleTypeDef *bus;
static UART_HandleTypeDef uart;
static uint8_t rx_byte;
static volatile uint8_t command_byte, uart_fault;
static uint32_t next_seq, last_send, last_report, last_expiry, last_reply_ms;
static char report_buffer[560];

static void encode32(uint32_t value, uint8_t *bytes)
{
    bytes[0] = (uint8_t)(value >> 24); bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8); bytes[3] = (uint8_t)value;
}
static uint32_t decode32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16)
         | ((uint32_t)bytes[2] << 8) | bytes[3];
}
static void make_payload(uint32_t seq, uint8_t *bytes)
{
    uint32_t pattern;
    switch (seq % 6U) {
    case 0: pattern = 0; break;
    case 1: pattern = UINT32_MAX; break;
    case 2: pattern = 0x55555555U; break;
    case 3: pattern = 0xAAAAAAAAU; break;
    case 4: pattern = seq ^ 0xA5C35A3CU; break;
    default:
        pattern = seq * 1664525U + 1013904223U;
        pattern ^= pattern >> 16; pattern *= 0x7FEB352DU;
        pattern ^= pattern >> 15; break;
    }
    encode32(seq, bytes); encode32(pattern, bytes + 4);
}

void HAL_UART_MspInit(UART_HandleTypeDef *handle)
{
    if (handle->Instance != LPUART1) return;
    RCC_PeriphCLKInitTypeDef clocks = {0};
    clocks.PeriphClockSelection = RCC_PERIPHCLK_LPUART1;
    clocks.Lpuart1ClockSelection = RCC_LPUART1CLKSOURCE_PCLK1;
    if (HAL_RCCEx_PeriphCLKConfig(&clocks) != HAL_OK) Error_Handler();
    __HAL_RCC_LPUART1_CLK_ENABLE(); __HAL_RCC_GPIOA_CLK_ENABLE();
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin = GPIO_PIN_2 | GPIO_PIN_3; gpio.Mode = GPIO_MODE_AF_PP;
    gpio.Pull = GPIO_NOPULL; gpio.Speed = GPIO_SPEED_FREQ_HIGH;
    gpio.Alternate = GPIO_AF12_LPUART1; HAL_GPIO_Init(GPIOA, &gpio);
    HAL_NVIC_SetPriority(LPUART1_IRQn, 3, 0); HAL_NVIC_EnableIRQ(LPUART1_IRQn);
}
void LPUART1_IRQHandler(void) { HAL_UART_IRQHandler(&uart); }
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *handle)
{
    if (handle != &uart) return;
    if (rx_byte == 'S' || rx_byte == 's' || rx_byte == 'P' || rx_byte == 'p' ||
        rx_byte == 'R' || rx_byte == 'r' || (rx_byte >= '1' && rx_byte <= '3')) {
        command_byte = rx_byte;
    }
    if (HAL_UART_Receive_IT(&uart, &rx_byte, 1) != HAL_OK) uart_fault = 1;
}
void HAL_UART_ErrorCallback(UART_HandleTypeDef *handle)
{
    if (handle == &uart) uart_fault = 1;
}
static void report(void)
{
    if (uart.gState != HAL_UART_STATE_READY) return;
    const char *state = canTest.fault ? "FAULT" : canTest.running ? "RUN" : "PAUSED";
    int length = snprintf(report_buffer, sizeof(report_buffer),
        "CAN1M G474 state=%s bitrate=1000000 rate=%lu queued=%lu tx_done=%lu echo=%lu pending=%lu bad=%lu unexpected=%lu timeout=%lu qfail=%lu rx_lost=%lu tef_lost=%lu err_events=%lu bo_events=%lu tec=%lu rec=%lu tec_max=%lu rec_max=%lu lec=%lu rtt_max_us=%lu late=%lu uart_err=%lu cmds=S:start,P:pause,R:reset,1:100,2:1000,3:2500\r\n",
        state, U(canTest.rate), U(canTest.queued), U(canTest.completed), U(canTest.replies),
        U(canTest.pending), U(canTest.bad_bytes), U(canTest.unexpected), U(canTest.timeouts),
        U(canTest.queue_fail), U(canTest.rx_lost), U(canTest.tx_event_lost),
        U(canTest.protocol_events), U(canTest.bus_off_events), U(canTest.tec), U(canTest.rec),
        U(canTest.max_tec), U(canTest.max_rec), U(canTest.last_error), U(canTest.max_rtt_us),
        U(canTest.late_sends), U(canTest.uart_errors));
    if (length > 0 && (size_t)length < sizeof(report_buffer)) {
        if (HAL_UART_Transmit_IT(&uart, (uint8_t *)report_buffer, (uint16_t)length) != HAL_OK)
            canTest.uart_errors++;
    }
}
static void configure_bus(void)
{
    FDCAN_FilterTypeDef filter = {0};
    filter.IdType = FDCAN_STANDARD_ID; filter.FilterIndex = 0;
    filter.FilterType = FDCAN_FILTER_MASK; filter.FilterConfig = FDCAN_FILTER_TO_RXFIFO0;
    filter.FilterID1 = RESPONSE_ID; filter.FilterID2 = 0x7FFU;
    if (HAL_FDCAN_ConfigFilter(bus, &filter) != HAL_OK ||
        HAL_FDCAN_ConfigGlobalFilter(bus, FDCAN_REJECT, FDCAN_REJECT,
            FDCAN_REJECT_REMOTE, FDCAN_REJECT_REMOTE) != HAL_OK ||
        HAL_FDCAN_Start(bus) != HAL_OK) Error_Handler();
}
static void restart(uint8_t run, uint32_t rate)
{
    canTest.running = 0;
    if (HAL_FDCAN_Stop(bus) != HAL_OK || HAL_FDCAN_DeInit(bus) != HAL_OK) Error_Handler();
    __HAL_RCC_FDCAN_FORCE_RESET(); __HAL_RCC_FDCAN_RELEASE_RESET();
    if (HAL_FDCAN_Init(bus) != HAL_OK) Error_Handler();
    configure_bus();
    memset((void *)&canTest, 0, sizeof(canTest)); memset(pending, 0, sizeof(pending));
    canTest.magic = 0x43414E31U; canTest.rate = rate; canTest.running = run;
    next_seq = 1; last_send = DWT->CYCCNT; last_expiry = HAL_GetTick(); last_reply_ms = 0;
    last_report = HAL_GetTick() - 1000U;
}
void CanLink_Init(FDCAN_HandleTypeDef *can)
{
    bus = can;
    /* Nominal HSI/PCLK1 = 16 MHz; 1 * (1 + 11 + 4) = 16 time quanta. */
    if (HAL_RCC_GetPCLK1Freq() != 16000000U || bus->Init.NominalPrescaler != 1 ||
        bus->Init.NominalTimeSeg1 != 11 || bus->Init.NominalTimeSeg2 != 4) Error_Handler();
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CYCCNT = 0; DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
    uart.Instance = LPUART1; uart.Init.BaudRate = 115200;
    uart.Init.WordLength = UART_WORDLENGTH_8B; uart.Init.StopBits = UART_STOPBITS_1;
    uart.Init.Parity = UART_PARITY_NONE; uart.Init.Mode = UART_MODE_TX_RX;
    uart.Init.HwFlowCtl = UART_HWCONTROL_NONE; uart.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
    uart.Init.ClockPrescaler = UART_PRESCALER_DIV1;
    if (HAL_UART_Init(&uart) != HAL_OK || HAL_UARTEx_DisableFifoMode(&uart) != HAL_OK ||
        HAL_UART_Receive_IT(&uart, &rx_byte, 1) != HAL_OK) Error_Handler();
    uint8_t bytes[8];
    const uint8_t known[8] = {0, 0, 0, 1, 255, 255, 255, 255};
    make_payload(1, bytes);
    if (memcmp(bytes, known, 8) != 0 || decode32(bytes) != 1) Error_Handler();
    configure_bus();
    canTest.magic = 0x43414E31U; canTest.rate = 100; next_seq = 1;
    last_report = HAL_GetTick() - 1000U;
}
void CanLink_Poll(void)
{
    if (uart_fault) {
        uart_fault = 0; canTest.uart_errors++;
        (void)HAL_UART_AbortReceive(&uart);
        if (HAL_UART_Receive_IT(&uart, &rx_byte, 1) != HAL_OK) uart_fault = 1;
    }
    uint8_t cmd = command_byte; command_byte = 0;
    if (cmd == 'R' || cmd == 'r') restart(0, canTest.rate);
    else if (cmd == 'S' || cmd == 's') restart(1, canTest.rate);
    else if (cmd == 'P' || cmd == 'p') canTest.running = 0;
    else if (cmd >= '1' && cmd <= '3') {
        uint32_t rate = cmd == '1' ? 100U : cmd == '2' ? 1000U : 2500U;
        restart(0, rate); /* Select rate, reset, and require S explicitly. */
    }

    while ((bus->Instance->TXEFS & FDCAN_TXEFS_EFFL) != 0U) {
        FDCAN_TxEventFifoTypeDef event;
        if (HAL_FDCAN_GetTxEvent(bus, &event) != HAL_OK) break;
        canTest.completed++;
    }
    while (HAL_FDCAN_GetRxFifoFillLevel(bus, FDCAN_RX_FIFO0) != 0U) {
        FDCAN_RxHeaderTypeDef header; uint8_t data[64], expected[8];
        if (HAL_FDCAN_GetRxMessage(bus, FDCAN_RX_FIFO0, &header, data) != HAL_OK) break;
        if (header.Identifier != RESPONSE_ID || header.IdType != FDCAN_STANDARD_ID ||
            header.RxFrameType != FDCAN_DATA_FRAME || header.FDFormat != FDCAN_CLASSIC_CAN ||
            header.DataLength != FDCAN_DLC_BYTES_8) { canTest.bad_bytes++; continue; }
        uint32_t seq = decode32(data); Pending *slot = &pending[seq % WINDOW];
        if (!slot->active || slot->seq != seq) { canTest.unexpected++; continue; }
        make_payload(seq, expected);
        if (memcmp(data, expected, 8) != 0) { canTest.bad_bytes++; continue; }
        uint32_t rtt = (DWT->CYCCNT - slot->cycles) / (SystemCoreClock / 1000000U);
        if (rtt > canTest.max_rtt_us) canTest.max_rtt_us = rtt;
        slot->active = 0; canTest.pending--; canTest.replies++; last_reply_ms = HAL_GetTick();
    }

    const uint32_t mask = FDCAN_FLAG_ARB_PROTOCOL_ERROR | FDCAN_FLAG_DATA_PROTOCOL_ERROR |
        FDCAN_FLAG_BUS_OFF | FDCAN_FLAG_RX_FIFO0_MESSAGE_LOST | FDCAN_FLAG_TX_EVT_FIFO_ELT_LOST;
    uint32_t flags = bus->Instance->IR & mask;
    if (flags) {
        if (flags & (FDCAN_FLAG_ARB_PROTOCOL_ERROR | FDCAN_FLAG_DATA_PROTOCOL_ERROR)) canTest.protocol_events++;
        if (flags & FDCAN_FLAG_BUS_OFF) canTest.bus_off_events++;
        if (flags & FDCAN_FLAG_RX_FIFO0_MESSAGE_LOST) canTest.rx_lost++;
        if (flags & FDCAN_FLAG_TX_EVT_FIFO_ELT_LOST) canTest.tx_event_lost++;
        __HAL_FDCAN_CLEAR_FLAG(bus, flags);
    }
    FDCAN_ProtocolStatusTypeDef protocol = {0}; FDCAN_ErrorCountersTypeDef errors = {0};
    if (HAL_FDCAN_GetProtocolStatus(bus, &protocol) == HAL_OK) {
        if (protocol.LastErrorCode >= 1U && protocol.LastErrorCode <= 6U) canTest.last_error = protocol.LastErrorCode;
        if (protocol.BusOff) canTest.fault = 1;
    }
    if (HAL_FDCAN_GetErrorCounters(bus, &errors) == HAL_OK) {
        canTest.tec = errors.TxErrorCnt; canTest.rec = errors.RxErrorCnt;
        if (canTest.tec > canTest.max_tec) canTest.max_tec = canTest.tec;
        if (canTest.rec > canTest.max_rec) canTest.max_rec = canTest.rec;
    }
    uint32_t now = HAL_GetTick();
    if (now != last_expiry) {
        last_expiry = now;
        for (uint32_t i = 0; i < WINDOW; i++) if (pending[i].active && now - pending[i].ms >= TIMEOUT_MS) {
            pending[i].active = 0; canTest.pending--; canTest.timeouts++;
        }
    }
    if (canTest.bad_bytes || canTest.unexpected || canTest.timeouts || canTest.queue_fail ||
        canTest.rx_lost || canTest.tx_event_lost || canTest.protocol_events || canTest.bus_off_events ||
        canTest.max_tec || canTest.max_rec) canTest.fault = 1;
    if (canTest.fault && canTest.running) {
        canTest.running = 0;
        if (bus->Instance->TXBRP) (void)HAL_FDCAN_AbortTxRequest(bus, bus->Instance->TXBRP);
    }
    uint32_t cycles = DWT->CYCCNT, period = SystemCoreClock / canTest.rate;
    if (canTest.running && cycles - last_send >= period) {
        if (cycles - last_send >= period * 2U) canTest.late_sends++;
        last_send = cycles; Pending *slot = &pending[next_seq % WINDOW];
        if (slot->active || HAL_FDCAN_GetTxFifoFreeLevel(bus) == 0) canTest.queue_fail++;
        else {
            FDCAN_TxHeaderTypeDef header = {0}; uint8_t bytes[8];
            header.Identifier = REQUEST_ID; header.IdType = FDCAN_STANDARD_ID;
            header.TxFrameType = FDCAN_DATA_FRAME; header.DataLength = FDCAN_DLC_BYTES_8;
            header.ErrorStateIndicator = FDCAN_ESI_ACTIVE; header.BitRateSwitch = FDCAN_BRS_OFF;
            header.FDFormat = FDCAN_CLASSIC_CAN; header.TxEventFifoControl = FDCAN_STORE_TX_EVENTS;
            header.MessageMarker = next_seq & 255U; make_payload(next_seq, bytes);
            if (HAL_FDCAN_AddMessageToTxFifoQ(bus, &header, bytes) == HAL_OK) {
                slot->seq = next_seq++; slot->cycles = cycles; slot->ms = now; slot->active = 1;
                canTest.queued++; canTest.pending++;
            } else canTest.queue_fail++;
        }
    }
    /* Paused heartbeat; running LED blinks only while validated echoes are recent. */
    uint32_t led_period = canTest.fault ? 100U : canTest.running ? 250U : 1000U;
    uint8_t led = !canTest.running || (canTest.replies && now - last_reply_ms < 500U);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, led && (now / led_period) % 2U ? GPIO_PIN_SET : GPIO_PIN_RESET);
    if (now - last_report >= 1000U) { last_report = now; report(); }
}
