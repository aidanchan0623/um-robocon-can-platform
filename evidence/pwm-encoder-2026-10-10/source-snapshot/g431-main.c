/* G431 CANDrive v1: signal-level PWM + quadrature bench test.
 * Original application; ST HAL/CMSIS/startup retain their own notices.
 * No motor-specific truth table, PID, braking or direction assumptions.
 */
#include "main.h"
#include <stddef.h>
#include <stdint.h>
#define MAGIC 0x43414E50UL
#define HOST_TIMEOUT_MS 500UL
#define TIMER_HZ 16000000UL
#ifndef CAN_BITRATE
#define CAN_BITRATE 1000000UL
#endif
#ifndef CAN_ONLY_TEST
#define CAN_ONLY_TEST 0
#endif
#ifndef IG42_ENCODER_PULLUPS
#define IG42_ENCODER_PULLUPS 0
#endif
#ifndef ENCODER_INPUT_FILTER
#define ENCODER_INPUT_FILTER 15U
#endif
_Static_assert(ENCODER_INPUT_FILTER<=15U,"TIM4 input filter range");
_Static_assert(CAN_BITRATE==250000UL || CAN_BITRATE==500000UL || CAN_BITRATE==1000000UL,"supported CAN bitrate");
typedef struct {
  uint32_t magic, version, tick, armed, fault, frequency, duty1, duty2;
  uint32_t raw, count_lo, count_hi, cps, ab, ack, result, snapshot;
  uint32_t heartbeat, command_seq, opcode, channel, duty, requested_hz, reserved;
} BenchMailbox;
_Static_assert(offsetof(BenchMailbox, heartbeat) == 64, "mailbox ABI");
volatile BenchMailbox bench = { .magic=MAGIC, .version=1, .frequency=1000 };
static uint32_t heartbeat_seen, heartbeat_at, command_seen, speed_at, publish_at;
static uint16_t encoder_previous;
static uint32_t encoder_ab_previous,encoder_states_seen,encoder_a_changes,encoder_b_changes;
static int64_t encoder_total, speed_previous;
static int32_t counts_per_second;
static uint32_t armed, duty1, duty2, frequency=1000, fault, result;
static FDCAN_HandleTypeDef can;
static uint32_t can_fault, remote_seq, remote_hb, remote_hb_at;
/* SWD-only fault evidence: no changes to the CAN telemetry/mailbox ABI. */
typedef struct {
  uint32_t magic,version,snapshot;
  uint32_t first_error_tick,first_psr,first_ecr,first_ir;
  uint32_t last_error_tick,last_psr,last_ecr,last_ir,error_observations;
  uint32_t fault_tick,fault_psr,fault_ecr,fault_ir;
} CanDiagnostics;
volatile CanDiagnostics can_diagnostics;
static uint32_t telemetry[16], tx_index=16;
static uint16_t telemetry_seq;
/* Independent unfiltered GPIO-edge observer. Close edges may coalesce;
 * compare with TIM4 rather than using this diagnostic as motor feedback. */
volatile uint32_t encoder_trace[16]={0x45585449UL,1};
static volatile int64_t edge_total;
static volatile uint32_t edge_stats[11],edge_previous;
static uint32_t read_ab(void)
{
  uint32_t idr=GPIOB->IDR;
  return ((idr>>7)&1U)|(((idr>>6)&1U)<<1);
}
void EXTI9_5_IRQHandler(void)
{
  static const int8_t steps[16]={0,-1,1,0,1,0,0,-1,-1,0,0,1,0,1,-1,0};
  uint32_t pending=EXTI->PR1&((1U<<6)|(1U<<7));
  if(!pending) return;
  EXTI->PR1=pending;
  uint32_t ab=read_ab(),changed=edge_previous^ab;
  int32_t step=steps[(edge_previous<<2)|ab];
  edge_total+=step;
  if(step>0) edge_stats[0]++;
  if(step<0) edge_stats[1]++;
  if(changed==3) edge_stats[2]++;
  if(!changed) edge_stats[3]++;
  if(pending==((1U<<6)|(1U<<7))) edge_stats[4]++;
  if(changed&1) edge_stats[(ab&1)?5:6]++;
  if(changed&2) edge_stats[(ab&2)?7:8]++;
  edge_stats[9]|=1U<<ab; edge_stats[10]++;
  edge_previous=ab;
}
static void edge_reset(void)
{
  uint32_t mask=__get_PRIMASK(); __disable_irq();
  edge_total=0;
  for(uint32_t i=0;i<11;i++) edge_stats[i]=0;
  edge_previous=read_ab(); edge_stats[9]=1U<<edge_previous;
  EXTI->PR1=(1U<<6)|(1U<<7);
  __set_PRIMASK(mask);
}
static void edge_publish(void)
{
  uint32_t copy[13],mask=__get_PRIMASK(); __disable_irq();
  copy[0]=(uint32_t)edge_total; copy[1]=(uint32_t)((uint64_t)edge_total>>32);
  for(uint32_t i=0;i<11;i++) copy[i+2]=edge_stats[i];
  __set_PRIMASK(mask);
  encoder_trace[2]++; __DMB();
  for(uint32_t i=0;i<13;i++) encoder_trace[i+3]=copy[i];
  __DMB(); encoder_trace[2]++;
}
static void stop_outputs(void)
{
  TIM3->CCR1=0; TIM3->CCR2=0;
  TIM3->EGR=TIM_EGR_UG;
  armed=0; duty1=0; duty2=0;
}
void Error_Handler(void)
{
  __HAL_RCC_GPIOC_CLK_ENABLE();
  GPIOC->BSRR=(GPIO_PIN_6|GPIO_PIN_7)<<16;
  GPIOC->MODER=(GPIOC->MODER & ~((3UL<<12)|(3UL<<14)))|(1UL<<12)|(1UL<<14);
  __disable_irq();
  for (;;) { }
}
static void clock_init(void)
{
  RCC_OscInitTypeDef osc={0}; RCC_ClkInitTypeDef clk={0};
  if (HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1)!=HAL_OK) Error_Handler();
  osc.OscillatorType=RCC_OSCILLATORTYPE_HSI;
  osc.HSIState=RCC_HSI_ON; osc.HSICalibrationValue=RCC_HSICALIBRATION_DEFAULT;
  osc.PLL.PLLState=RCC_PLL_NONE;
  if (HAL_RCC_OscConfig(&osc)!=HAL_OK) Error_Handler();
  clk.ClockType=RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK|RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  clk.SYSCLKSource=RCC_SYSCLKSOURCE_HSI; clk.AHBCLKDivider=RCC_SYSCLK_DIV1;
  clk.APB1CLKDivider=RCC_HCLK_DIV1; clk.APB2CLKDivider=RCC_HCLK_DIV1;
  if (HAL_RCC_ClockConfig(&clk,FLASH_LATENCY_0)!=HAL_OK) Error_Handler();
}
static void timers_init(void)
{
  GPIO_InitTypeDef pin={0};
  __HAL_RCC_GPIOC_CLK_ENABLE(); __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_TIM3_CLK_ENABLE(); __HAL_RCC_TIM4_CLK_ENABLE();
  /* PWM2=PC6/TIM3_CH1, PWM1=PC7/TIM3_CH2. Active-high, 3.3-V logic. */
  HAL_GPIO_WritePin(GPIOC,GPIO_PIN_6|GPIO_PIN_7,GPIO_PIN_RESET);
  pin.Pin=GPIO_PIN_6|GPIO_PIN_7; pin.Mode=GPIO_MODE_OUTPUT_PP;
  pin.Pull=GPIO_NOPULL; pin.Speed=GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOC,&pin);
  TIM3->CR1=TIM_CR1_ARPE; TIM3->PSC=0; TIM3->ARR=TIMER_HZ/frequency-1;
  TIM3->CCR1=0; TIM3->CCR2=0;
  TIM3->CCMR1=(6UL<<TIM_CCMR1_OC1M_Pos)|TIM_CCMR1_OC1PE|
               (6UL<<TIM_CCMR1_OC2M_Pos)|TIM_CCMR1_OC2PE;
  TIM3->CCER=TIM_CCER_CC1E|TIM_CCER_CC2E; TIM3->EGR=TIM_EGR_UG;
  /* CAN-only image: PWM pins stay GPIO LOW, timer outputs disabled; no encoder. */
  if(CAN_ONLY_TEST) { TIM3->CCER=0; return; }
  pin.Mode=GPIO_MODE_AF_PP; pin.Alternate=GPIO_AF2_TIM3;
  HAL_GPIO_Init(GPIOC,&pin); TIM3->CR1|=TIM_CR1_CEN;
  /* Encoder B=PB6/TIM4_CH1, A=PB7/TIM4_CH2. IG42 build enables 3.3-V
   * internal pulls for open-collector signals; other builds retain no pulls.
   * HAL_MspInit disables the PB6 UCPD dead-battery pull-down.
   * ICxF=15: stronger equal filtering on A/B for the slow IG42 bench test.
   * This reduces input bandwidth; do not assume high-speed qualification.
   */
  /* Keep encoder configuration independent of the preceding PWM pin setup. */
  GPIO_InitTypeDef encoder_pin={0};
  encoder_pin.Pin=GPIO_PIN_6|GPIO_PIN_7; encoder_pin.Mode=GPIO_MODE_AF_PP;
  encoder_pin.Pull=IG42_ENCODER_PULLUPS?GPIO_PULLUP:GPIO_NOPULL; encoder_pin.Speed=GPIO_SPEED_FREQ_LOW;
  encoder_pin.Alternate=GPIO_AF2_TIM4; HAL_GPIO_Init(GPIOB,&encoder_pin);
  __HAL_RCC_TIM4_FORCE_RESET(); __HAL_RCC_TIM4_RELEASE_RESET();
  TIM4->CR1=0; TIM4->PSC=0; TIM4->ARR=65535;
  TIM4->CCMR1=TIM_CCMR1_CC1S_0|TIM_CCMR1_CC2S_0|
              (ENCODER_INPUT_FILTER<<TIM_CCMR1_IC1F_Pos)|(ENCODER_INPUT_FILTER<<TIM_CCMR1_IC2F_Pos);
  TIM4->CCER=TIM_CCER_CC1E|TIM_CCER_CC2E;
  TIM4->SMCR=TIM_SMCR_SMS_0|TIM_SMCR_SMS_1; /* TI1 + TI2, x4 */
  TIM4->EGR=TIM_EGR_UG; TIM4->CNT=0; TIM4->CR1=TIM_CR1_CEN;
  encoder_previous=(uint16_t)TIM4->CNT;
  uint32_t idr=GPIOB->IDR;
  encoder_ab_previous=((idr>>7)&1UL)|(((idr>>6)&1UL)<<1);
  encoder_states_seen=1UL<<encoder_ab_previous;
  SYSCFG->EXTICR[1]=(SYSCFG->EXTICR[1]&~0xFF00UL)|0x1100UL;
  EXTI->RTSR1|=(1U<<6)|(1U<<7); EXTI->FTSR1|=(1U<<6)|(1U<<7);
  edge_reset();
  HAL_NVIC_SetPriority(EXTI9_5_IRQn,5,0);
  EXTI->IMR1|=(1U<<6)|(1U<<7); HAL_NVIC_EnableIRQ(EXTI9_5_IRQn);
}
/* Sampled at ~1 kHz for SLOW hand-turn diagnosis only. These are not edge
 * totals: fast pulses can be missed. Hardware TIM4 still does all counting. */
static void encoder_observe(void)
{
  uint32_t idr=GPIOB->IDR;
  uint32_t ab=((idr>>7)&1UL)|(((idr>>6)&1UL)<<1);
  uint32_t changed=ab^encoder_ab_previous;
  if((changed&1U) && encoder_a_changes<4095) encoder_a_changes++;
  if((changed&2U) && encoder_b_changes<4095) encoder_b_changes++;
  encoder_states_seen|=1UL<<ab; encoder_ab_previous=ab;
}
static uint32_t encoder_diagnostic_word(void)
{
  const uint32_t input_fields=TIM_CCMR1_CC1S|TIM_CCMR1_CC2S|
                             TIM_CCMR1_IC1PSC|TIM_CCMR1_IC2PSC;
  uint32_t configured=(GPIOB->MODER&(15UL<<12))==(10UL<<12) &&
    (GPIOB->AFR[0]&(255UL<<24))==(0x22UL<<24) &&
    (GPIOB->PUPDR&(15UL<<12))==(IG42_ENCODER_PULLUPS?(5UL<<12):0) &&
    (RCC->APB1ENR1&RCC_APB1ENR1_TIM4EN) &&
    (TIM4->CR1&TIM_CR1_CEN) &&
    (TIM4->SMCR&(TIM_SMCR_SMS|TIM_SMCR_ECE))==(TIM_SMCR_SMS_0|TIM_SMCR_SMS_1) &&
    (TIM4->CCMR1&input_fields)==(TIM_CCMR1_CC1S_0|TIM_CCMR1_CC2S_0) &&
    (TIM4->CCMR1&(TIM_CCMR1_IC1F|TIM_CCMR1_IC2F))==
      ((ENCODER_INPUT_FILTER<<TIM_CCMR1_IC1F_Pos)|(ENCODER_INPUT_FILTER<<TIM_CCMR1_IC2F_Pos)) &&
    (TIM4->CCER&0xFFU)==(TIM_CCER_CC1E|TIM_CCER_CC2E) &&
    TIM4->PSC==0 && TIM4->ARR==65535;
  /* Low two bits remain ABI-compatible. Bit 7 marks diagnostic support. */
  return encoder_ab_previous|(encoder_states_seen<<2)|(configured<<6)|0x80UL|
         (encoder_a_changes<<8)|(encoder_b_changes<<20);
}
static void can_init(void)
{
  can_diagnostics.magic=0x43414E45UL; can_diagnostics.version=1;
  RCC_PeriphCLKInitTypeDef clock={0}; GPIO_InitTypeDef pin={0};
  clock.PeriphClockSelection=RCC_PERIPHCLK_FDCAN;
  clock.FdcanClockSelection=RCC_FDCANCLKSOURCE_PCLK1;
  if(HAL_RCCEx_PeriphCLKConfig(&clock)!=HAL_OK) Error_Handler();
  __HAL_RCC_FDCAN_CLK_ENABLE(); __HAL_RCC_GPIOA_CLK_ENABLE();
  pin.Pin=GPIO_PIN_11|GPIO_PIN_12; pin.Mode=GPIO_MODE_AF_PP;
  pin.Pull=GPIO_NOPULL; pin.Speed=GPIO_SPEED_FREQ_HIGH; pin.Alternate=GPIO_AF9_FDCAN1;
  HAL_GPIO_Init(GPIOA,&pin);
  can.Instance=FDCAN1; can.Init.ClockDivider=FDCAN_CLOCK_DIV1;
  can.Init.FrameFormat=FDCAN_FRAME_CLASSIC; can.Init.Mode=FDCAN_MODE_NORMAL;
  can.Init.AutoRetransmission=DISABLE; can.Init.TransmitPause=DISABLE;
  can.Init.ProtocolException=DISABLE;
  /* 16 MHz / prescaler / (1+11+4), 75% sample point; HSI bench clock. */
  can.Init.NominalPrescaler=1000000UL/CAN_BITRATE; can.Init.NominalSyncJumpWidth=4;
  can.Init.NominalTimeSeg1=11; can.Init.NominalTimeSeg2=4;
  can.Init.DataPrescaler=1; can.Init.DataSyncJumpWidth=1;
  can.Init.DataTimeSeg1=2; can.Init.DataTimeSeg2=1;
  can.Init.StdFiltersNbr=1; can.Init.ExtFiltersNbr=0;
  can.Init.TxFifoQueueMode=FDCAN_TX_FIFO_OPERATION;
  if(HAL_FDCAN_Init(&can)!=HAL_OK) Error_Handler();
  FDCAN_FilterTypeDef f={0}; f.IdType=FDCAN_STANDARD_ID;
  f.FilterType=FDCAN_FILTER_RANGE; f.FilterConfig=FDCAN_FILTER_TO_RXFIFO0;
  f.FilterID1=0x320; f.FilterID2=0x321;
  if(HAL_FDCAN_ConfigFilter(&can,&f)!=HAL_OK ||
     HAL_FDCAN_ConfigGlobalFilter(&can,FDCAN_REJECT,FDCAN_REJECT,FDCAN_REJECT_REMOTE,FDCAN_REJECT_REMOTE)!=HAL_OK ||
     HAL_FDCAN_Start(&can)!=HAL_OK) Error_Handler();
}
static uint32_t unpack32(const uint8_t *d)
{ return (uint32_t)d[0]|((uint32_t)d[1]<<8)|((uint32_t)d[2]<<16)|((uint32_t)d[3]<<24); }
static void can_record(uint32_t now,uint32_t psr,uint32_t ir,uint32_t failed)
{
  uint32_t lec=psr&FDCAN_PSR_LEC;
  uint32_t new_error=lec>0 && lec<7;
  uint32_t first_fault=failed && !can_fault;
  if(!new_error && !first_fault) return;
  uint32_t ecr=FDCAN1->ECR;
  can_diagnostics.snapshot++; __DMB();
  if(new_error) {
    if(!can_diagnostics.error_observations) {
      can_diagnostics.first_error_tick=now; can_diagnostics.first_psr=psr;
      can_diagnostics.first_ecr=ecr; can_diagnostics.first_ir=ir;
    }
    can_diagnostics.last_error_tick=now; can_diagnostics.last_psr=psr;
    can_diagnostics.last_ecr=ecr; can_diagnostics.last_ir=ir;
    can_diagnostics.error_observations++;
  }
  if(first_fault) {
    can_diagnostics.fault_tick=now; can_diagnostics.fault_psr=psr;
    can_diagnostics.fault_ecr=ecr; can_diagnostics.fault_ir=ir;
  }
  __DMB(); can_diagnostics.snapshot++;
}
static void can_poll(uint32_t now)
{
  /* Bus-off, error-passive or receive loss latches until reset, never auto-rearm. */
  uint32_t psr=FDCAN1->PSR,ir=FDCAN1->IR;
  uint32_t failed=(psr & (FDCAN_PSR_BO|FDCAN_PSR_EP)) || (ir & FDCAN_IR_RF0L);
  can_record(now,psr,ir,failed);
  if(failed) can_fault=1;
  if(can_fault) { stop_outputs(); fault=6; return; }
  while(HAL_FDCAN_GetRxFifoFillLevel(&can,FDCAN_RX_FIFO0)) {
    FDCAN_RxHeaderTypeDef h={0}; uint8_t d[64];
    if(HAL_FDCAN_GetRxMessage(&can,FDCAN_RX_FIFO0,&h,d)!=HAL_OK) {
      can_record(now,FDCAN1->PSR,FDCAN1->IR,1);
      can_fault=1; stop_outputs(); fault=6; return;
    }
    if(h.IdType!=FDCAN_STANDARD_ID || h.RxFrameType!=FDCAN_DATA_FRAME ||
       h.FDFormat!=FDCAN_CLASSIC_CAN || h.DataLength!=FDCAN_DLC_BYTES_8) continue;
    if(h.Identifier==0x321 && unpack32(d)==0x48424E43UL) {
      uint32_t hb=unpack32(d+4);
      if(hb!=remote_hb) { remote_hb=hb; remote_hb_at=now; bench.heartbeat=hb; }
    } else if(h.Identifier==0x320) {
      uint32_t seq=unpack32(d+4);
      if(seq==remote_seq) continue;
      remote_seq=seq;
      bench.opcode=d[0]; bench.channel=d[1];
      uint32_t value=(uint32_t)d[2]|((uint32_t)d[3]<<8);
      bench.duty=value; bench.requested_hz=value;
      if(d[0]!=2 && (!remote_hb || (uint32_t)(now-remote_hb_at)>300)) {
        stop_outputs(); result=1; command_seen=seq; fault=1; continue;
      }
      bench.command_seq=seq;
    }
  }
}
static void can_telemetry(void)
{
  if(tx_index>=16 || can_fault || !HAL_FDCAN_GetTxFifoFreeLevel(&can)) return;
  uint32_t value=telemetry[tx_index];
  uint8_t d[8]={(uint8_t)telemetry_seq,(uint8_t)(telemetry_seq>>8),(uint8_t)tx_index,0xA1,
    (uint8_t)value,(uint8_t)(value>>8),(uint8_t)(value>>16),(uint8_t)(value>>24)};
  FDCAN_TxHeaderTypeDef h={0}; h.Identifier=0x330; h.IdType=FDCAN_STANDARD_ID;
  h.TxFrameType=FDCAN_DATA_FRAME; h.DataLength=FDCAN_DLC_BYTES_8;
  h.ErrorStateIndicator=FDCAN_ESI_ACTIVE; h.BitRateSwitch=FDCAN_BRS_OFF;
  h.FDFormat=FDCAN_CLASSIC_CAN; h.TxEventFifoControl=FDCAN_NO_TX_EVENTS;
  if(HAL_FDCAN_AddMessageToTxFifoQ(&can,&h,d)==HAL_OK) tx_index++;
}
static void command(uint32_t now)
{
  uint32_t seq=bench.command_seq;
  if (seq==command_seen) return;
  __DMB();
  uint32_t op=bench.opcode, ch=bench.channel, d=bench.duty, hz=bench.requested_hz;
  __DMB();
  if (seq!=bench.command_seq) return;
  command_seen=seq; result=0;
  /* Reject every command except STOP in the diagnostic image, including SWD requests. */
  if(CAN_ONLY_TEST && op!=2) { stop_outputs(); result=12; return; }
  switch(op) {
  case 1:
    stop_outputs();
    if (!heartbeat_seen || (uint32_t)(now-heartbeat_at)>HOST_TIMEOUT_MS) result=1;
    else { armed=1; fault=0; }
    break;
  case 2: stop_outputs(); fault=0; break;
  case 3:
    if (!armed || (ch!=1 && ch!=2) || d>1000 ||
        (ch==1 && d && duty2) || (ch==2 && d && duty1)) { result=2; stop_outputs(); break; }
    if(ch==1) duty1=d; else duty2=d;
    TIM3->CCR2=((TIM3->ARR+1)*duty1)/1000;
    TIM3->CCR1=((TIM3->ARR+1)*duty2)/1000;
    break;
  case 4:
    if (armed) { result=3; stop_outputs(); break; }
    encoder_previous=(uint16_t)TIM4->CNT; encoder_total=0;
    edge_reset();
    speed_previous=0; speed_at=now; counts_per_second=0; break;
  case 5:
    if (armed || hz<100 || hz>20000) { result=4; stop_outputs(); break; }
    frequency=TIMER_HZ/((TIMER_HZ+hz/2)/hz);
    TIM3->ARR=(TIMER_HZ+hz/2)/hz-1; TIM3->EGR=TIM_EGR_UG; break;
  default: result=5; stop_outputs(); break;
  }
}
int main(void)
{
  HAL_Init(); clock_init(); timers_init(); can_init();
  bench.reserved=CAN_ONLY_TEST;
  /* Independent watchdog: nominal ~1 s (LSI dependent), not frozen in debug.
   * A firmware freeze resets to disarmed startup. Not a safety-rated stop.
   */
  IWDG->KR=0xCCCC; /* start LSI before waiting for register synchronization */
  IWDG->KR=0x5555; IWDG->PR=3; IWDG->RLR=999;
  while(IWDG->SR) { }
  IWDG->KR=0xAAAA;
  uint32_t previous_tick=HAL_GetTick(); speed_at=previous_tick;
  for (;;) {
    uint32_t now=HAL_GetTick();
    if (now==previous_tick) continue;
    if ((uint32_t)(now-previous_tick)>10) { stop_outputs(); fault=3; }
    previous_tick=now;
    can_poll(now);
    uint16_t raw=0;
    if(!CAN_ONLY_TEST) {
      raw=(uint16_t)TIM4->CNT;
      uint16_t difference=(uint16_t)(raw-encoder_previous);
      encoder_total+=difference<32768U?(int32_t)difference:(int32_t)difference-65536;
      encoder_previous=raw;
      encoder_observe();
    }
    uint32_t hb=bench.heartbeat;
    if (hb!=heartbeat_seen) { heartbeat_seen=hb; heartbeat_at=now; }
    if (armed && (uint32_t)(now-heartbeat_at)>HOST_TIMEOUT_MS) { stop_outputs(); fault=1; }
    if(!can_fault) command(now);
    can_telemetry();
    IWDG->KR=0xAAAA;
    if ((uint32_t)(now-publish_at)<20) continue;
    publish_at=now;
    if(!CAN_ONLY_TEST) edge_publish();
    bench.snapshot++; __DMB();
    bench.tick=now; bench.armed=armed; bench.fault=fault;
    bench.frequency=frequency; bench.duty1=duty1; bench.duty2=duty2; bench.raw=raw;
    bench.count_lo=(uint32_t)encoder_total;
    bench.count_hi=(uint32_t)((uint64_t)encoder_total>>32);
    uint32_t dt=now-speed_at;
    if(dt>=100) {
      int64_t rate=(encoder_total-speed_previous)*1000/(int64_t)dt;
      counts_per_second=(int32_t)rate; speed_previous=encoder_total; speed_at=now;
    }
    bench.cps=(uint32_t)counts_per_second;
    bench.ack=command_seen; bench.result=result;
    bench.ab=CAN_ONLY_TEST?0:encoder_diagnostic_word();
    __DMB(); bench.snapshot++;
    if(tx_index>=16) {
      const volatile uint32_t *words=(const volatile uint32_t *)&bench;
      for(uint32_t i=0;i<16;i++) telemetry[i]=words[i];
      telemetry_seq++; tx_index=0;
    }
    IWDG->KR=0xAAAA;
  }
}
