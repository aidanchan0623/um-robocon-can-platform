#include "bldc_control.h"

static uint8_t near_zero(int32_t speed)
{
    return speed >= -BLDC_STOPPED_ERPM && speed <= BLDC_STOPPED_ERPM;
}

uint8_t Bldc_LinkFresh(const BldcControl *control, uint32_t now)
{
    return control->telemetry_seen &&
           (uint32_t)(now - control->telemetry_ms) <= BLDC_VESC_TIMEOUT_MS;
}

void Bldc_Disarm(BldcControl *control)
{
    control->armed = 0;
    control->requested_erpm = 0;
    control->output_erpm = 0;
    control->last_direction = 0;
}

uint8_t Bldc_Arm(BldcControl *control, uint32_t now)
{
    Bldc_Disarm(control);
    if (!Bldc_LinkFresh(control, now) || !near_zero(control->measured_erpm)) return 0;
    control->armed = 1;
    control->host_ms = now;
    return 1;
}

uint8_t Bldc_Request(BldcControl *control, int32_t erpm, uint32_t now)
{
    if (erpm < -BLDC_MAX_ERPM || erpm > BLDC_MAX_ERPM) {
        Bldc_Disarm(control);
        return 0;
    }
    /* A late packet must not revive an expired lease between control ticks. */
    if (!control->armed ||
        (uint32_t)(now - control->host_ms) > BLDC_HOST_TIMEOUT_MS ||
        !Bldc_LinkFresh(control, now)) {
        Bldc_Disarm(control);
        return 0;
    }
    control->requested_erpm = erpm;
    control->host_ms = now;
    return 1;
}

uint8_t Bldc_Update(BldcControl *control, uint32_t now)
{
    if (!control->armed ||
        (uint32_t)(now - control->host_ms) > BLDC_HOST_TIMEOUT_MS ||
        !Bldc_LinkFresh(control, now)) {
        Bldc_Disarm(control);
        return 0;
    }
    if (control->requested_erpm == 0) {
        control->output_erpm = 0;
        if (near_zero(control->measured_erpm)) control->last_direction = 0;
        return 0;
    }
    int8_t direction = control->requested_erpm > 0 ? 1 : -1;
    /* Let the shaft coast down before allowing a direction reversal. */
    if (control->last_direction != 0 && direction != control->last_direction &&
        !near_zero(control->measured_erpm)) {
        control->output_erpm = 0;
        return 0;
    }
    if (direction != control->last_direction) control->output_erpm = 0;
    control->last_direction = direction;
    int32_t delta = control->requested_erpm - control->output_erpm;
    if (delta > BLDC_RAMP_STEP_ERPM) delta = BLDC_RAMP_STEP_ERPM;
    if (delta < -BLDC_RAMP_STEP_ERPM) delta = -BLDC_RAMP_STEP_ERPM;
    control->output_erpm += delta;
    return 1;
}
