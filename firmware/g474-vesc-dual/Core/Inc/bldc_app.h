#ifndef BLDC_APP_H
#define BLDC_APP_H
#include "stm32g4xx_hal.h"
void BldcApp_Init(FDCAN_HandleTypeDef *can, UART_HandleTypeDef *uart);
void BldcApp_Poll(void);
#endif
