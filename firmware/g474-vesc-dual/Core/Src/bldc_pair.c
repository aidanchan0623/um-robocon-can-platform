#include "bldc_pair.h"
void BldcPair_Disarm(BldcControl c[2])
{
    Bldc_Disarm(&c[0]); Bldc_Disarm(&c[1]);
}
uint8_t BldcPair_Arm(BldcControl c[2], uint32_t now)
{
    BldcPair_Disarm(c);
    if (!Bldc_Arm(&c[0], now) || !Bldc_Arm(&c[1], now)) {
        BldcPair_Disarm(c); return 0;
    }
    return 1;
}
uint8_t BldcPair_Request(BldcControl c[2], int32_t erpm, uint32_t now)
{
    if (!Bldc_Request(&c[0], erpm, now) || !Bldc_Request(&c[1], erpm, now)) {
        BldcPair_Disarm(c); return 0;
    }
    return 1;
}
uint8_t BldcPair_Update(BldcControl c[2], uint32_t now)
{
    uint8_t first = Bldc_Update(&c[0], now);
    uint8_t second = Bldc_Update(&c[1], now);
    if (!c[0].armed || !c[1].armed) { BldcPair_Disarm(c); return 0; }
    return (uint8_t)(first | (second << 1));
}
