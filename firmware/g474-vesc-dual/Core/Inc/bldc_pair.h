#ifndef BLDC_PAIR_H
#define BLDC_PAIR_H
#include "bldc_control.h"
void BldcPair_Disarm(BldcControl controls[2]);
uint8_t BldcPair_Arm(BldcControl controls[2], uint32_t now);
uint8_t BldcPair_Request(BldcControl controls[2], int32_t erpm, uint32_t now);
/* Returns a bitmask of motors that need an RPM command. */
uint8_t BldcPair_Update(BldcControl controls[2], uint32_t now);
#endif
