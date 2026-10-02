#ifndef BLDC_SELFTEST_H
#define BLDC_SELFTEST_H
#include <stdint.h>
/* Pure logic checks. Never send CAN frames or enable a motor. */
uint32_t Bldc_SelfTest(void);
#endif
