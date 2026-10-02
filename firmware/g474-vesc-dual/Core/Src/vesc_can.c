#include "vesc_can.h"

void Vesc_EncodeInt32(int32_t value, uint8_t bytes[4])
{
    uint32_t bits = (uint32_t)value;
    bytes[0] = (uint8_t)(bits >> 24);
    bytes[1] = (uint8_t)(bits >> 16);
    bytes[2] = (uint8_t)(bits >> 8);
    bytes[3] = (uint8_t)bits;
}

int32_t Vesc_DecodeInt32(const uint8_t bytes[4])
{
    uint32_t value = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16)
                   | ((uint32_t)bytes[2] << 8) | bytes[3];
    if (value <= INT32_MAX) return (int32_t)value;
    return -1 - (int32_t)(UINT32_MAX - value);
}

static int16_t decode_int16(const uint8_t *bytes)
{
    uint16_t value = ((uint16_t)bytes[0] << 8) | bytes[1];
    if (value <= INT16_MAX) return (int16_t)value;
    return (int16_t)(-1 - (int32_t)(UINT16_MAX - value));
}

HAL_StatusTypeDef Vesc_SendValue(FDCAN_HandleTypeDef *can, uint8_t id,
                                uint32_t packet, int32_t value)
{
    FDCAN_TxHeaderTypeDef header = {0};
    uint8_t data[4];
    header.Identifier = (packet << 8) | id;
    header.IdType = FDCAN_EXTENDED_ID;
    header.TxFrameType = FDCAN_DATA_FRAME;
    header.DataLength = FDCAN_DLC_BYTES_4;
    header.ErrorStateIndicator = FDCAN_ESI_ACTIVE;
    header.BitRateSwitch = FDCAN_BRS_OFF;
    header.FDFormat = FDCAN_CLASSIC_CAN;
    header.TxEventFifoControl = FDCAN_NO_TX_EVENTS;
    Vesc_EncodeInt32(value, data);
    if (HAL_FDCAN_GetTxFifoFreeLevel(can) == 0) return HAL_BUSY;
    return HAL_FDCAN_AddMessageToTxFifoQ(can, &header, data);
}

uint8_t Vesc_DecodeStatus(const FDCAN_RxHeaderTypeDef *header,
                         const uint8_t *data, uint32_t now, VescStatus *status)
{
    if (header->IdType != FDCAN_EXTENDED_ID ||
        header->RxFrameType != FDCAN_DATA_FRAME ||
        header->FDFormat != FDCAN_CLASSIC_CAN ||
        header->DataLength != FDCAN_DLC_BYTES_8 ||
        (header->Identifier >> 8) != VESC_PACKET_STATUS) return 0;
    status->id = (uint8_t)header->Identifier;
    status->erpm = Vesc_DecodeInt32(data);
    status->current_deciamp = decode_int16(data + 4);
    status->duty_permille = decode_int16(data + 6);
    status->last_ms = now;
    status->seen = 1;
    return 1;
}
