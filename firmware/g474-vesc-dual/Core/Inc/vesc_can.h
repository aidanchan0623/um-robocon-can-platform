#ifndef VESC_CAN_H
#define VESC_CAN_H
#include "stm32g4xx_hal.h"
#include <stdint.h>

/* VESC classic CAN: extended identifier = (packet type << 8) | node ID. */
#define VESC_PACKET_SET_CURRENT 1U
#define VESC_PACKET_SET_RPM 3U
#define VESC_PACKET_STATUS 9U
#define VESC_PACKET_STATUS_5 27U

typedef struct {
    uint8_t id;
    uint8_t seen;
    uint32_t last_ms;
    int32_t erpm;
    int16_t current_deciamp;
    int16_t duty_permille;
} VescStatus;

void Vesc_EncodeInt32(int32_t value, uint8_t bytes[4]);
int32_t Vesc_DecodeInt32(const uint8_t bytes[4]);
HAL_StatusTypeDef Vesc_SendValue(FDCAN_HandleTypeDef *can, uint8_t id,
                                uint32_t packet, int32_t value);
uint8_t Vesc_DecodeStatus(const FDCAN_RxHeaderTypeDef *header,
                         const uint8_t *data, uint32_t now, VescStatus *status);
#endif
