#ifndef BLDC_CONTROL_H
#define BLDC_CONTROL_H
#include <stdint.h>

/* Bench defaults; current limits must also be configured inside the VESC. */
#define BLDC_MAX_ERPM 3500
#define BLDC_HOST_TIMEOUT_MS 250U
#define BLDC_VESC_TIMEOUT_MS 300U
#define BLDC_STOPPED_ERPM 350
#define BLDC_RAMP_STEP_ERPM 70

typedef struct {
    uint8_t armed;
    uint8_t telemetry_seen;
    uint32_t host_ms;
    uint32_t telemetry_ms;
    int32_t measured_erpm;
    int32_t requested_erpm;
    int32_t output_erpm;
    int8_t last_direction;
} BldcControl;

uint8_t Bldc_LinkFresh(const BldcControl *control, uint32_t now);
uint8_t Bldc_Arm(BldcControl *control, uint32_t now);
void Bldc_Disarm(BldcControl *control);
uint8_t Bldc_Request(BldcControl *control, int32_t erpm, uint32_t now);
/* Call every 20 ms. Returns 1 for RPM drive, 0 for torque-off (0 A). */
uint8_t Bldc_Update(BldcControl *control, uint32_t now);
#endif
