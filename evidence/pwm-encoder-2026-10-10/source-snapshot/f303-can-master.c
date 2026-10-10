/* F303 CAN bridge: remote PWM only; explicit arm, no automatic retry/recovery. */
#include "main.h"
#include <stdint.h>
#include <stddef.h>
#define MAGIC 0x43414E50UL
#ifndef CAN_BITRATE
#define CAN_BITRATE 1000000UL
#endif
_Static_assert(CAN_BITRATE==250000UL || CAN_BITRATE==500000UL || CAN_BITRATE==1000000UL,"supported CAN bitrate");
typedef struct {
  uint32_t magic,version,tick,armed,fault,frequency,duty1,duty2;
  uint32_t raw,count_lo,count_hi,cps,ab,ack,result,snapshot;
  uint32_t heartbeat,command_seq,opcode,channel,duty,requested_hz,reserved;
} BenchMailbox;
volatile BenchMailbox bench={.magic=MAGIC,.version=1,.fault=4,.frequency=1000};
_Static_assert(offsetof(BenchMailbox,heartbeat)==64,"mailbox ABI");
CAN_HandleTypeDef hcan;
static uint32_t remote[16],assembly[16],mask,received_at,hb_seen,hb_at,hb_sent_at;
static uint32_t cmd_seen,pending_seq,pending_at,pending,pending_op,local_result,remote_valid,publish_at;
static uint16_t packet_seq;
#define RX_QUEUE_SIZE 64U
_Static_assert((RX_QUEUE_SIZE & (RX_QUEUE_SIZE-1))==0,"RX queue must be a power of two");
enum { FAULT_CONTROLLER=1, FAULT_FIFO=2, FAULT_QUEUE=4, FAULT_RECEIVE=8, FAULT_LOOP=16 };
typedef struct {
  uint32_t magic,version,snapshot,fault_bits,first_reason,first_tick;
  uint32_t first_esr,first_rf0r,first_hal_error,max_loop_ms;
  uint32_t rx_frames,invalid_frames,complete_snapshots,queue_high_water;
  uint32_t fifo_overruns,queue_overruns,receive_errors,loop_stalls;
  uint32_t telemetry_age_ms,remote_valid,remote_fault;
  uint32_t controller_ready,startup_controller_events,startup_first_tick,startup_first_esr,startup_last_esr;
} BridgeDiagnostics;
_Static_assert(sizeof(BridgeDiagnostics)==26*4,"diagnostic ABI");
volatile BridgeDiagnostics diagnostics={.magic=0x43414E44UL,.version=2,.telemetry_age_ms=0xFFFFFFFFUL};
typedef struct { CAN_RxHeaderTypeDef header; uint8_t data[8]; } RxFrame;
static RxFrame rx_queue[RX_QUEUE_SIZE];
static volatile uint32_t rx_head,rx_tail,fault_bits;
static volatile uint32_t first_reason,first_tick,first_esr,first_rf0r,first_hal_error;
static volatile uint32_t max_loop_ms,rx_frames,invalid_frames,complete_snapshots,queue_high_water;
static volatile uint32_t fifo_overruns,queue_overruns,receive_errors,loop_stalls;
static uint32_t controller_qualified,stable_since,startup_error_active;
static uint32_t startup_controller_events,startup_first_tick,startup_first_esr,startup_last_esr;
static void latch_fault(uint32_t reason)
{
  uint32_t irq=__get_PRIMASK(); __disable_irq();
  if(!fault_bits) {
    first_reason=reason; first_tick=HAL_GetTick(); first_esr=CAN->ESR;
    first_rf0r=CAN->RF0R; first_hal_error=hcan.ErrorCode;
  }
  fault_bits|=reason; __DMB(); __set_PRIMASK(irq);
}
/* Interrupt drains the three-entry hardware FIFO into a bounded SPSC queue.
 * No command execution or telemetry assembly occurs in interrupt context. */
void USB_LP_CAN_RX0_IRQHandler(void)
{
  if(CAN->RF0R & CAN_RF0R_FOVR0) {
    fifo_overruns++; latch_fault(FAULT_FIFO);
    __HAL_CAN_CLEAR_FLAG(&hcan,CAN_FLAG_FOV0);
  }
  for(uint32_t n=0;n<8 && HAL_CAN_GetRxFifoFillLevel(&hcan,CAN_RX_FIFO0);n++) {
    CAN_RxHeaderTypeDef header; uint8_t data[8];
    if(HAL_CAN_GetRxMessage(&hcan,CAN_RX_FIFO0,&header,data)!=HAL_OK) {
      receive_errors++; latch_fault(FAULT_RECEIVE); break;
    }
    rx_frames++;
    uint32_t head=rx_head,depth=head-rx_tail;
    if(depth>=RX_QUEUE_SIZE) { queue_overruns++; latch_fault(FAULT_QUEUE); continue; }
    RxFrame *slot=&rx_queue[head & (RX_QUEUE_SIZE-1)]; slot->header=header;
    for(uint32_t i=0;i<8;i++) slot->data[i]=data[i];
    __DMB(); rx_head=head+1;
    if(depth+1>queue_high_water) queue_high_water=depth+1;
  }
}
static uint32_t master_fault_code(void)
{
  if(first_reason==FAULT_CONTROLLER)return 24;
  if(first_reason==FAULT_FIFO)return 21;
  if(first_reason==FAULT_QUEUE)return 22;
  if(first_reason==FAULT_RECEIVE)return 23;
  if(first_reason==FAULT_LOOP)return 20;
  return 0;
}
static uint32_t unpack32(const uint8_t *d)
{ return (uint32_t)d[0]|((uint32_t)d[1]<<8)|((uint32_t)d[2]<<16)|((uint32_t)d[3]<<24); }
void Error_Handler(void) { __disable_irq(); for(;;){} }
static void init(void)
{
  RCC_OscInitTypeDef o={0}; RCC_ClkInitTypeDef c={0};
  o.OscillatorType=RCC_OSCILLATORTYPE_HSI; o.HSIState=RCC_HSI_ON;
  o.HSICalibrationValue=RCC_HSICALIBRATION_DEFAULT; o.PLL.PLLState=RCC_PLL_ON;
  o.PLL.PLLSource=RCC_PLLSOURCE_HSI; o.PLL.PREDIV=RCC_PREDIV_DIV2; o.PLL.PLLMUL=RCC_PLL_MUL16;
  if(HAL_RCC_OscConfig(&o)!=HAL_OK) Error_Handler();
  c.ClockType=RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK|RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  c.SYSCLKSource=RCC_SYSCLKSOURCE_PLLCLK; c.AHBCLKDivider=RCC_SYSCLK_DIV1;
  c.APB1CLKDivider=RCC_HCLK_DIV2; c.APB2CLKDivider=RCC_HCLK_DIV1;
  if(HAL_RCC_ClockConfig(&c,FLASH_LATENCY_2)!=HAL_OK) Error_Handler();
  hcan.Instance=CAN; hcan.Init.Prescaler=2000000UL/CAN_BITRATE; hcan.Init.Mode=CAN_MODE_NORMAL;
  hcan.Init.SyncJumpWidth=CAN_SJW_4TQ; hcan.Init.TimeSeg1=CAN_BS1_11TQ;
  hcan.Init.TimeSeg2=CAN_BS2_4TQ; /* PCLK1=32MHz / prescaler / 16 */
  hcan.Init.AutoBusOff=DISABLE; hcan.Init.AutoRetransmission=DISABLE;
  hcan.Init.ReceiveFifoLocked=ENABLE; hcan.Init.TransmitFifoPriority=ENABLE;
  if(HAL_CAN_Init(&hcan)!=HAL_OK) Error_Handler();
  CAN_FilterTypeDef f={0}; f.FilterMode=CAN_FILTERMODE_IDMASK; f.FilterScale=CAN_FILTERSCALE_32BIT;
  f.FilterIdHigh=0x330<<5; f.FilterMaskIdHigh=0x7FF<<5;
  f.FilterMaskIdLow=6; /* IDE/RTR must both be zero */
  f.FilterFIFOAssignment=CAN_RX_FIFO0; f.FilterActivation=ENABLE;
  if(HAL_CAN_ConfigFilter(&hcan,&f)!=HAL_OK || HAL_CAN_Start(&hcan)!=HAL_OK) Error_Handler();
  HAL_NVIC_SetPriority(USB_LP_CAN_RX0_IRQn,2,0);
  if(HAL_CAN_ActivateNotification(&hcan,CAN_IT_RX_FIFO0_MSG_PENDING|CAN_IT_RX_FIFO0_OVERRUN)!=HAL_OK) Error_Handler();
  HAL_NVIC_EnableIRQ(USB_LP_CAN_RX0_IRQn);
  IWDG->KR=0xCCCC; IWDG->KR=0x5555; IWDG->PR=3; IWDG->RLR=999;
  while(IWDG->SR){} IWDG->KR=0xAAAA;
}
static int send(uint32_t id,uint8_t *d)
{
  if((CAN->ESR & (CAN_ESR_BOFF|CAN_ESR_EPVF)) || !HAL_CAN_GetTxMailboxesFreeLevel(&hcan)) return 0;
  CAN_TxHeaderTypeDef h={0}; uint32_t mb;
  h.StdId=id; h.IDE=CAN_ID_STD; h.RTR=CAN_RTR_DATA; h.DLC=8;
  return HAL_CAN_AddTxMessage(&hcan,&h,d,&mb)==HAL_OK;
}
static void receive(uint32_t now)
{
  uint32_t esr=CAN->ESR;
  if(esr & (CAN_ESR_BOFF|CAN_ESR_EPVF)) {
    if(controller_qualified) latch_fault(FAULT_CONTROLLER);
    else {
      /* Pre-operational state: no heartbeat/Arm/duty is permitted. Never force
       * bus-off recovery or erase evidence; wait for a healthy joined bus. */
      if(!startup_error_active) {
        startup_controller_events++;
        if(startup_controller_events==1) {startup_first_tick=now;startup_first_esr=esr;}
      }
      startup_error_active=1; startup_last_esr=esr; stable_since=0;
    }
  } else startup_error_active=0;
  /* Bound main-loop work even if the bus is continuously busy. */
  for(uint32_t n=0;n<RX_QUEUE_SIZE && rx_tail!=rx_head;n++) {
    uint32_t tail=rx_tail; __DMB();
    RxFrame frame=rx_queue[tail & (RX_QUEUE_SIZE-1)];
    __DMB(); rx_tail=tail+1;
    CAN_RxHeaderTypeDef h=frame.header; const uint8_t *d=frame.data;
    if(h.StdId!=0x330 || h.IDE!=CAN_ID_STD || h.RTR!=CAN_RTR_DATA || h.DLC!=8 || d[3]!=0xA1 || d[2]>=16) {
      invalid_frames++; continue;
    }
    uint16_t seq=(uint16_t)d[0]|((uint16_t)d[1]<<8);
    if(seq!=packet_seq){packet_seq=seq;mask=0;}
    assembly[d[2]]=unpack32(d+4); mask|=1UL<<d[2];
    if(mask==0xFFFF && assembly[0]==MAGIC && assembly[1]==1 && !(assembly[15]&1)) {
      for(uint32_t i=0;i<16;i++) remote[i]=assembly[i];
      received_at=now; remote_valid=1; mask=0; complete_snapshots++;
      if(pending && remote[13]==pending_seq){pending=0;local_result=remote[14];}
    }
  }
}
static void poll(uint32_t now)
{
  receive(now);
  int telemetry_fresh=remote_valid && (uint32_t)(now-received_at)<250;
  if(!controller_qualified) {
    if(fault_bits || !telemetry_fresh || remote[4] ||
       (CAN->ESR & (CAN_ESR_EWGF|CAN_ESR_EPVF|CAN_ESR_BOFF))) stable_since=0;
    else if(!stable_since) stable_since=now;
    else if((uint32_t)(now-stable_since)>=100) controller_qualified=1;
  }
  uint32_t hb=bench.heartbeat;
  if(hb!=hb_seen){hb_seen=hb;hb_at=now;}
  int host_alive=hb_seen && (uint32_t)(now-hb_at)<700;
  int link_alive=telemetry_fresh && !fault_bits && controller_qualified;
  if(host_alive && link_alive && (uint32_t)(now-hb_sent_at)>=50) {
    uint8_t d[8]={0x43,0x4E,0x42,0x48,(uint8_t)hb,(uint8_t)(hb>>8),(uint8_t)(hb>>16),(uint8_t)(hb>>24)};
    if(send(0x321,d)) hb_sent_at=now;
  }
  uint32_t seq=bench.command_seq;
  if(seq!=cmd_seen) {
    __DMB(); uint32_t op=bench.opcode,ch=bench.channel,value=(op==5)?bench.requested_hz:bench.duty;
    __DMB();
    if(seq==bench.command_seq) {
      cmd_seen=seq; pending_seq=seq; pending_at=now; pending_op=op; pending=0; local_result=10;
      int valid=op>=1 && op<=5 && (op!=3 || ((ch==1 || ch==2) && value<=1000)) &&
                (op!=5 || (value>=100 && value<=20000));
      /* STOP remains available under a software latch; it never clears the latch. */
      if(valid && (op==2 || (host_alive && link_alive))) {
        uint8_t d[8]={(uint8_t)op,(uint8_t)ch,(uint8_t)value,(uint8_t)(value>>8),
          (uint8_t)seq,(uint8_t)(seq>>8),(uint8_t)(seq>>16),(uint8_t)(seq>>24)};
        if(send(0x320,d)){pending=1;local_result=0;}
      }
    }
  }
  if(pending && ((uint32_t)(now-pending_at)>350 || (pending_op!=2 && (!host_alive || !link_alive)))) {
    HAL_CAN_AbortTxRequest(&hcan,CAN_TX_MAILBOX0|CAN_TX_MAILBOX1|CAN_TX_MAILBOX2);
    pending=0;local_result=11;
  }
  if((uint32_t)(now-publish_at)<20)return;
  publish_at=now; bench.snapshot++; __DMB();
  bench.tick=now; bench.armed=telemetry_fresh?remote[3]:0;
  bench.fault=fault_bits?master_fault_code():(!telemetry_fresh?4:(remote[4]?remote[4]:(!controller_qualified?25:0)));
  bench.frequency=remote_valid?remote[5]:1000;
  bench.duty1=remote[6];bench.duty2=remote[7];bench.raw=remote[8];
  bench.count_lo=remote[9];bench.count_hi=remote[10];bench.cps=remote[11];bench.ab=remote[12];
  bench.ack=(!pending && cmd_seen)?pending_seq:remote[13];
  bench.result=(!pending && cmd_seen)?local_result:remote[14];
  __DMB();bench.snapshot++;
  /* Separate seqlock: captures the first fault without overwriting its evidence. */
  uint32_t irq=__get_PRIMASK(); __disable_irq();
  diagnostics.snapshot++; __DMB();
  diagnostics.fault_bits=fault_bits; diagnostics.first_reason=first_reason;
  diagnostics.first_tick=first_tick; diagnostics.first_esr=first_esr;
  diagnostics.first_rf0r=first_rf0r; diagnostics.first_hal_error=first_hal_error;
  diagnostics.max_loop_ms=max_loop_ms; diagnostics.rx_frames=rx_frames;
  diagnostics.invalid_frames=invalid_frames; diagnostics.complete_snapshots=complete_snapshots;
  diagnostics.queue_high_water=queue_high_water; diagnostics.fifo_overruns=fifo_overruns;
  diagnostics.queue_overruns=queue_overruns; diagnostics.receive_errors=receive_errors;
  diagnostics.loop_stalls=loop_stalls;
  diagnostics.telemetry_age_ms=remote_valid?(uint32_t)(now-received_at):0xFFFFFFFFUL;
  diagnostics.remote_valid=remote_valid; diagnostics.remote_fault=remote[4];
  diagnostics.controller_ready=controller_qualified && !fault_bits;
  diagnostics.startup_controller_events=startup_controller_events;
  diagnostics.startup_first_tick=startup_first_tick; diagnostics.startup_first_esr=startup_first_esr;
  diagnostics.startup_last_esr=startup_last_esr;
  __DMB(); diagnostics.snapshot++; __set_PRIMASK(irq);
}
int main(void)
{
  HAL_Init();init(); uint32_t last=HAL_GetTick();
  for(;;){uint32_t now=HAL_GetTick();if(now==last)continue;
    uint32_t gap=(uint32_t)(now-last); if(gap>max_loop_ms)max_loop_ms=gap;
    if(gap>10){loop_stalls++;latch_fault(FAULT_LOOP);}
    last=now;poll(now);IWDG->KR=0xAAAA;
  }
}
