#include "bldc_app.h"
#include "bldc_control.h"
#include "vesc_can.h"
#include "bldc_selftest.h"
#include "main.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static FDCAN_HandleTypeDef *bus;
static UART_HandleTypeDef *console;
static BldcControl control;
static uint8_t vesc_id = 1;
static uint8_t last_seen_id = 255;
static uint8_t rx_byte;
static volatile uint8_t serial_fault;
static volatile uint16_t ring_head, ring_tail;
static uint8_t ring[256];
static char line[64];
static uint8_t line_length;
static uint32_t last_tick, last_report;
static uint32_t can_received, can_sent, can_failed;
static uint32_t last_can_send_ms;
static uint8_t can_bus_off;
static uint8_t stop_pending;
static uint32_t selftest_passed;

static void reply(const char *text)
{
    /* Bounded output; RX continues in interrupts while sending. */
    (void)HAL_UART_Transmit(console, (const uint8_t *)text, (uint16_t)strlen(text), 25);
}

static void flush_tx(void)
{
    /* Cancel queued drive packets so they cannot run after a stop or reconnect. */
    uint32_t pending = bus->Instance->TXBRP;
    if (pending != 0) (void)HAL_FDCAN_AbortTxRequest(bus, pending);
}

static void disarm(void)
{
    Bldc_Disarm(&control);
    flush_tx();
    stop_pending = 1;
}

static uint8_t parse_number(const char *text, long *value)
{
    char *end;
    if (*text == '\0') return 0;
    errno = 0;
    *value = strtol(text, &end, 10);
    return errno != ERANGE && end != text && *end == '\0';
}

static void report(uint32_t now)
{
    char text[220];
    uint32_t age = control.telemetry_seen ? now - control.telemetry_ms : UINT32_MAX;
    FDCAN_ErrorCountersTypeDef errors = {0};
    (void)HAL_FDCAN_GetErrorCounters(bus, &errors);
    snprintf(text, sizeof(text),
        "T ms=%lu armed=%u id=%u link=%u age=%lu erpm=%ld request=%ld out=%ld rx=%lu tx=%lu fail=%lu tec=%lu bo=%u seen=%u test=%lu\r\n",
        (unsigned long)now, control.armed, vesc_id, Bldc_LinkFresh(&control, now),
        (unsigned long)age, (long)control.measured_erpm,
        (long)control.requested_erpm, (long)control.output_erpm,
        (unsigned long)can_received, (unsigned long)can_sent,
        (unsigned long)can_failed, (unsigned long)errors.TxErrorCnt,
        can_bus_off, last_seen_id, (unsigned long)selftest_passed);
    reply(text);
}

static void command(const char *text, uint32_t now)
{
    long value;
    if (strcmp(text, "?") == 0) { report(now); return; }
    if (strcmp(text, "D") == 0) { disarm(); reply("OK DISARMED\r\n"); return; }
    if (strcmp(text, "S") == 0) {
        control.requested_erpm = 0;
        control.output_erpm = 0;
        flush_tx();
        stop_pending = 1;
        /* S does not renew the host lease; use R 0 to keep an armed idle lease. */
        reply("OK STOP TORQUE_OFF\r\n");
        return;
    }
    if (strcmp(text, "A") == 0) {
        if (!can_bus_off && Bldc_Arm(&control, now)) reply("OK ARMED\r\n");
        else { disarm(); reply("ERR ARM NEED_FRESH_STATUS_AND_STOPPED_MOTOR\r\n"); }
        return;
    }
    if (strncmp(text, "I ", 2) == 0 && parse_number(text + 2, &value)) {
        if (control.armed || value < 0 || value > 253) {
            disarm(); reply("ERR ID DISARM_FIRST RANGE_0_253\r\n"); return;
        }
        disarm();
        vesc_id = (uint8_t)value;
        control.telemetry_seen = 0;
        reply("OK ID\r\n"); return;
    }
    if (strncmp(text, "R ", 2) == 0 && parse_number(text + 2, &value)) {
        if (value < -BLDC_MAX_ERPM || value > BLDC_MAX_ERPM) {
            disarm(); reply("ERR RPM RANGE_3500\r\n"); return;
        }
        if (can_bus_off || !Bldc_Request(&control, (int32_t)value, now)) {
            disarm(); reply("ERR DRIVE DISARMED_OR_LINK_STALE\r\n"); return;
        }
        if (value == 0) {
            control.output_erpm = 0;
            flush_tx(); stop_pending = 1;
        }
        return;
    }
    disarm(); reply("ERR COMMAND\r\n");
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *uart)
{
    if (uart != console) return;
    uint16_t next = (ring_head + 1U) & 255U;
    if (next == ring_tail) serial_fault = 1;
    else { ring[ring_head] = rx_byte; __DMB(); ring_head = next; }
    if (HAL_UART_Receive_IT(console, &rx_byte, 1) != HAL_OK) serial_fault = 1;
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *uart)
{
    if (uart == console) serial_fault = 1;
}

void BldcApp_Init(FDCAN_HandleTypeDef *can, UART_HandleTypeDef *uart)
{
    bus = can; console = uart;
    selftest_passed = Bldc_SelfTest();
    if (selftest_passed == 0) Error_Handler();
    FDCAN_FilterTypeDef filter = {0};
    filter.IdType = FDCAN_EXTENDED_ID;
    filter.FilterIndex = 0;
    filter.FilterType = FDCAN_FILTER_MASK;
    filter.FilterConfig = FDCAN_FILTER_TO_RXFIFO0;
    /* Listen to all extended frames to help identify an incorrectly set VESC ID. */
    filter.FilterID1 = 0; filter.FilterID2 = 0;
    if (HAL_FDCAN_ConfigFilter(bus, &filter) != HAL_OK) Error_Handler();
    if (HAL_FDCAN_ConfigGlobalFilter(bus, FDCAN_REJECT, FDCAN_REJECT,
          FDCAN_REJECT_REMOTE, FDCAN_REJECT_REMOTE) != HAL_OK) Error_Handler();
    if (HAL_FDCAN_Start(bus) != HAL_OK) Error_Handler();
    if (HAL_UART_Receive_IT(console, &rx_byte, 1) != HAL_OK) Error_Handler();
    reply("G474_VESC_CAN v1 baud=250000 uart=115200 max_erpm=3500 DISARMED\r\n");
}

void BldcApp_Poll(void)
{
    uint32_t now = HAL_GetTick();
    FDCAN_ProtocolStatusTypeDef protocol = {0};
    if (HAL_FDCAN_GetProtocolStatus(bus, &protocol) == HAL_OK) {
        can_bus_off = (uint8_t)protocol.BusOff;
        if (can_bus_off) {
            disarm();
            /* Clear INIT to recover; recovery never automatically arms drive. */
            CLEAR_BIT(bus->Instance->CCCR, FDCAN_CCCR_INIT);
        }
    }

    /* Bounded work per loop even on an unrelated, busy bus. */
    for (uint32_t count = 0; count < 3 &&
         HAL_FDCAN_GetRxFifoFillLevel(bus, FDCAN_RX_FIFO0) != 0; ++count) {
        FDCAN_RxHeaderTypeDef header;
        uint8_t data[64];
        if (HAL_FDCAN_GetRxMessage(bus, FDCAN_RX_FIFO0, &header, data) == HAL_OK) {
            VescStatus status = {0};
            if (Vesc_DecodeStatus(&header, data, now, &status)) {
                last_seen_id = status.id;
                if (status.id == vesc_id) {
                    control.telemetry_seen = 1;
                    control.telemetry_ms = now;
                    control.measured_erpm = status.erpm;
                    can_received++;
                }
            }
        }
    }

    if (serial_fault) {
        disarm();
        (void)HAL_UART_AbortReceive(console);
        __disable_irq();
        ring_tail = ring_head;
        serial_fault = 0;
        __enable_irq();
        line_length = 0;
        if (HAL_UART_Receive_IT(console, &rx_byte, 1) != HAL_OK) serial_fault = 1;
        reply("ERR UART DISARMED\r\n");
    }
    for (uint32_t count = 0; count < 128 && ring_tail != ring_head; ++count) {
        uint8_t byte = ring[ring_tail];
        ring_tail = (ring_tail + 1U) & 255U;
        if (byte == '\r') continue;
        if (byte == '\n') {
            line[line_length] = '\0';
            command(line, HAL_GetTick());
            line_length = 0;
        } else if (byte < 32 || byte > 126 || line_length >= sizeof(line) - 1) {
            serial_fault = 1; break;
        } else line[line_length++] = (char)byte;
    }

    now = HAL_GetTick();
    if ((uint32_t)(now - last_tick) >= 20U || stop_pending) {
        last_tick = now;
        uint8_t was_armed = control.armed;
        uint8_t drive = Bldc_Update(&control, now);
        if (was_armed && !control.armed) stop_pending = 1;
        /* Bound the life of a pending packet independently of retransmission. */
        if (bus->Instance->TXBRP != 0 && (now - last_can_send_ms) >= 20U) flush_tx();
        if (!drive) flush_tx();
        if (!can_bus_off && (control.armed || Bldc_LinkFresh(&control, now) || stop_pending)) {
            HAL_StatusTypeDef result = Vesc_SendValue(bus, vesc_id,
                drive ? VESC_PACKET_SET_RPM : VESC_PACKET_SET_CURRENT,
                drive ? control.output_erpm : 0);
            if (result == HAL_OK) { can_sent++; last_can_send_ms = now; }
            else { can_failed++; disarm(); }
        }
        stop_pending = 0;
        HAL_GPIO_WritePin(GPIOA, GPIO_PIN_5, control.armed ? GPIO_PIN_SET : GPIO_PIN_RESET);
    }
    if ((uint32_t)(now - last_report) >= 200U) {
        last_report = now; report(now);
    }
}
