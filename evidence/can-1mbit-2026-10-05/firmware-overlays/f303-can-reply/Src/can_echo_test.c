/* Bench-only Classic CAN echo. No motor commands. Counters readable via SWD. */
#include "can_echo_test.h"
#include <string.h>

#define QUEUE_SIZE 64U
typedef struct {
    uint32_t magic, ready, polls, received, queued, completed, invalid;
    uint32_t queue_overflow, rx_overrun, tx_failed, hal_fail, error_events;
    uint32_t bus_off, tec, rec, max_tec, max_rec, last_error, pending;
} EchoStats;
volatile EchoStats canEcho;
static CAN_HandleTypeDef *bus;
static uint8_t queue[QUEUE_SIZE][8];
static uint32_t head, tail, last_rx_ms;
static CAN_TxHeaderTypeDef reply;

void USB_HP_CAN_TX_IRQHandler(void) { HAL_CAN_IRQHandler(bus); }
void HAL_CAN_TxMailbox0CompleteCallback(CAN_HandleTypeDef *can)
{ if (can == bus) canEcho.completed++; }
void HAL_CAN_TxMailbox1CompleteCallback(CAN_HandleTypeDef *can)
{ if (can == bus) canEcho.completed++; }
void HAL_CAN_TxMailbox2CompleteCallback(CAN_HandleTypeDef *can)
{ if (can == bus) canEcho.completed++; }
void HAL_CAN_ErrorCallback(CAN_HandleTypeDef *can)
{ if (can == bus) canEcho.tx_failed++; }

void CanEcho_Init(CAN_HandleTypeDef *can)
{
    bus = can;
    if (HAL_RCC_GetPCLK1Freq() != 32000000U || bus->Init.Prescaler != 2 ||
        bus->Init.TimeSeg1 != CAN_BS1_11TQ || bus->Init.TimeSeg2 != CAN_BS2_4TQ)
        Error_Handler();
    CAN_FilterTypeDef filter = {0};
    filter.FilterBank = 0; filter.FilterMode = CAN_FILTERMODE_IDMASK;
    filter.FilterScale = CAN_FILTERSCALE_32BIT;
    filter.FilterIdHigh = 0x601U << 5;
    filter.FilterMaskIdHigh = 0x7FFU << 5;
    filter.FilterMaskIdLow = 0x6U; /* Require standard identifier and data frame. */
    filter.FilterFIFOAssignment = CAN_RX_FIFO0; filter.FilterActivation = ENABLE;
    if (HAL_CAN_ConfigFilter(bus, &filter) != HAL_OK || HAL_CAN_Start(bus) != HAL_OK)
        Error_Handler();
    reply.StdId = 0x602U; reply.IDE = CAN_ID_STD;
    reply.RTR = CAN_RTR_DATA; reply.DLC = 8;
    canEcho.magic = 0x43414E32U; canEcho.ready = 1;
    HAL_NVIC_SetPriority(USB_HP_CAN_TX_IRQn, 2, 0);
    HAL_NVIC_EnableIRQ(USB_HP_CAN_TX_IRQn);
    if (HAL_CAN_ActivateNotification(bus, CAN_IT_TX_MAILBOX_EMPTY) != HAL_OK) Error_Handler();
}

void CanEcho_Poll(void)
{
    canEcho.polls++;
    /* Successful transmission completions are counted by the CAN TX interrupt. */
    if (__HAL_CAN_GET_FLAG(bus, CAN_FLAG_FOV0)) {
        canEcho.rx_overrun++; __HAL_CAN_CLEAR_FLAG(bus, CAN_FLAG_FOV0);
    }
    while (HAL_CAN_GetRxFifoFillLevel(bus, CAN_RX_FIFO0)) {
        CAN_RxHeaderTypeDef header; uint8_t data[8];
        if (HAL_CAN_GetRxMessage(bus, CAN_RX_FIFO0, &header, data) != HAL_OK) {
            canEcho.hal_fail++; break;
        }
        if (header.IDE != CAN_ID_STD || header.StdId != 0x601U ||
            header.RTR != CAN_RTR_DATA || header.DLC != 8) { canEcho.invalid++; continue; }
        canEcho.received++; last_rx_ms = HAL_GetTick();
        if (head - tail >= QUEUE_SIZE) { canEcho.queue_overflow++; continue; }
        memcpy(queue[head % QUEUE_SIZE], data, 8); head++;
    }
    while (head != tail && HAL_CAN_GetTxMailboxesFreeLevel(bus)) {
        uint32_t mailbox;
        if (HAL_CAN_AddTxMessage(bus, &reply, queue[tail % QUEUE_SIZE], &mailbox) != HAL_OK) {
            canEcho.hal_fail++; break;
        }
        tail++; canEcho.queued++;
    }
    canEcho.pending = head - tail;
    uint32_t esr = bus->Instance->ESR;
    canEcho.tec = (esr & CAN_ESR_TEC) >> CAN_ESR_TEC_Pos;
    canEcho.rec = (esr & CAN_ESR_REC) >> CAN_ESR_REC_Pos;
    if (canEcho.tec > canEcho.max_tec) canEcho.max_tec = canEcho.tec;
    if (canEcho.rec > canEcho.max_rec) canEcho.max_rec = canEcho.rec;
    if (esr & CAN_ESR_BOFF) canEcho.bus_off = 1;
    uint32_t lec = (esr & CAN_ESR_LEC) >> CAN_ESR_LEC_Pos;
    if (lec >= 1U && lec <= 6U) {
        canEcho.last_error = lec; canEcho.error_events++;
        /* LEC=7 software marker; subsequent hardware errors replace it. */
        bus->Instance->ESR = CAN_ESR_LEC;
    }
    uint32_t now = HAL_GetTick();
    uint8_t fault = canEcho.invalid || canEcho.queue_overflow || canEcho.rx_overrun ||
        canEcho.tx_failed || canEcho.hal_fail || canEcho.error_events || canEcho.bus_off ||
        canEcho.max_tec || canEcho.max_rec;
    uint32_t period = fault ? 100U : canEcho.received && now - last_rx_ms < 500U ? 250U : 1000U;
    HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, (now / period) % 2U ? GPIO_PIN_SET : GPIO_PIN_RESET);
}
