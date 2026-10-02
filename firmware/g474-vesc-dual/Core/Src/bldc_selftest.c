#include "bldc_selftest.h"
#include "bldc_control.h"
#include "bldc_pair.h"
#include "vesc_can.h"
#include <string.h>

#define CHECK(condition) do { if (!(condition)) return 0; ++passed; } while (0)

uint32_t Bldc_SelfTest(void)
{
    uint32_t passed = 0;
    BldcControl c = {0};
    CHECK(!Bldc_Arm(&c, 100));
    c.telemetry_seen = 1; c.telemetry_ms = 100; c.measured_erpm = 0;
    CHECK(Bldc_Arm(&c, 100));
    CHECK(Bldc_Request(&c, 1400, 100));
    CHECK(Bldc_Update(&c, 120) && c.output_erpm == 70);
    c.measured_erpm = 1400;
    CHECK(Bldc_Request(&c, -1400, 130));
    CHECK(!Bldc_Update(&c, 140) && c.output_erpm == 0 && c.armed);
    c.measured_erpm = 0;
    CHECK(Bldc_Update(&c, 160) && c.output_erpm == -70);
    CHECK(Bldc_Request(&c, 0, 170));
    CHECK(!Bldc_Update(&c, 180) && c.output_erpm == 0 && c.armed);
    c.telemetry_ms = 430;
    CHECK(!Bldc_Update(&c, 430) && !c.armed);
    CHECK(!Bldc_Request(&c, 1400, 431));
    c.telemetry_ms = 500;
    CHECK(Bldc_Arm(&c, 500));
    CHECK(!Bldc_Request(&c, 1400, 751) && !c.armed);
    c.telemetry_ms = 800;
    CHECK(Bldc_Arm(&c, 800));
    c.host_ms = 1090;
    CHECK(!Bldc_Update(&c, 1101) && !c.armed);
    c.telemetry_ms = 1200;
    CHECK(Bldc_Arm(&c, 1200));
    CHECK(!Bldc_Request(&c, 3501, 1201) && !c.armed);
    c.telemetry_ms = UINT32_MAX - 30U;
    CHECK(Bldc_Arm(&c, UINT32_MAX - 30U));
    CHECK(Bldc_Request(&c, 1400, 10U));
    uint8_t bytes[4];
    Vesc_EncodeInt32(1400, bytes);
    const uint8_t positive[] = {0x00, 0x00, 0x05, 0x78};
    CHECK(memcmp(bytes, positive, 4) == 0);
    Vesc_EncodeInt32(-1400, bytes);
    const uint8_t negative[] = {0xff, 0xff, 0xfa, 0x88};
    CHECK(memcmp(bytes, negative, 4) == 0 && Vesc_DecodeInt32(bytes) == -1400);
    Vesc_EncodeInt32(INT32_MIN, bytes);
    CHECK(Vesc_DecodeInt32(bytes) == INT32_MIN);
    FDCAN_RxHeaderTypeDef header = {0};
    header.Identifier = (VESC_PACKET_STATUS << 8) | 1;
    header.IdType = FDCAN_EXTENDED_ID;
    header.RxFrameType = FDCAN_DATA_FRAME;
    header.FDFormat = FDCAN_CLASSIC_CAN;
    header.DataLength = FDCAN_DLC_BYTES_8;
    uint8_t data[] = {0xff,0xff,0xfa,0x88,0xff,0xf6,0xff,0x9c};
    VescStatus status = {0};
    CHECK(Vesc_DecodeStatus(&header, data, 2000, &status) && status.id == 1 &&
          status.erpm == -1400 && status.current_deciamp == -10 &&
          status.duty_permille == -100 && status.last_ms == 2000);
    header.DataLength = FDCAN_DLC_BYTES_4;
    CHECK(!Vesc_DecodeStatus(&header, data, 2001, &status));
    header.DataLength = FDCAN_DLC_BYTES_8; header.IdType = FDCAN_STANDARD_ID;
    CHECK(!Vesc_DecodeStatus(&header, data, 2002, &status));
    BldcControl pair[2] = {0};
    pair[0].telemetry_seen = 1; pair[0].telemetry_ms = 100;
    CHECK(!BldcPair_Arm(pair, 100) && !pair[0].armed && !pair[1].armed);
    pair[1].telemetry_seen = 1; pair[1].telemetry_ms = 100;
    pair[1].measured_erpm = 500;
    CHECK(!BldcPair_Arm(pair, 100) && !pair[0].armed);
    pair[1].measured_erpm = 0;
    CHECK(BldcPair_Arm(pair, 100));
    CHECK(BldcPair_Request(pair, 1400, 100));
    CHECK(BldcPair_Update(pair, 120) == 3 && pair[0].output_erpm == 70 && pair[1].output_erpm == 70);
    pair[0].measured_erpm = 1400; pair[1].measured_erpm = 0;
    CHECK(BldcPair_Request(pair, -1400, 130));
    CHECK(BldcPair_Update(pair, 140) == 2 && pair[0].output_erpm == 0 && pair[1].output_erpm == -70);
    CHECK(BldcPair_Request(pair, 0, 150));
    CHECK(BldcPair_Update(pair, 160) == 0 && pair[0].armed && pair[1].armed);
    pair[0].telemetry_ms = 450;
    CHECK(!BldcPair_Request(pair, 1400, 450) && !pair[0].armed && !pair[1].armed);
    pair[0].measured_erpm = 0; pair[1].telemetry_ms = 500; pair[0].telemetry_ms = 500;
    CHECK(BldcPair_Arm(pair, 500));
    CHECK(BldcPair_Request(pair, 1400, 500));
    pair[0].telemetry_ms = 800; pair[0].host_ms = pair[1].host_ms = 800;
    CHECK(BldcPair_Update(pair, 801) == 0 && !pair[0].armed && !pair[1].armed);
    CHECK(!BldcPair_Request(pair, 1400, 802));
    pair[0].telemetry_ms = pair[1].telemetry_ms = UINT32_MAX - 30U;
    CHECK(BldcPair_Arm(pair, UINT32_MAX - 30U));
    CHECK(BldcPair_Request(pair, 1400, 10U));
    CHECK(BldcPair_Update(pair, 20U) == 3);
    return passed;
}
