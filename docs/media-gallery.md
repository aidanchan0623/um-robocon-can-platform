# Prototype and debugging gallery

These photographs and the video were supplied by Aidan on 2 October 2026. Original media bytes are retained under descriptive filenames. The supply date and WhatsApp filenames do not independently establish recording dates. Captions distinguish visible observations from the separate test records.

## CANDrive v1 bare PCB

<img src="../hardware/images/photos/candrive-v1-bare-pcb.jpeg" alt="Bare CANDrive v1 PCB with labelled CAN, external MCU, PWM, encoder, UART and debug connections" width="650">

The unpopulated board shows the physical prototype and its labelled interfaces. This is not an assembled-board photograph and does not show the repaired transceiver joints. Visible PWM and encoder connections indicate intended features, not verified operation.

## Two-motor bench

<img src="../hardware/images/photos/dual-motor-bench.jpeg" alt="Bench arrangement with two motors, controllers, custom board, Nucleo and test wiring" width="480">

The photograph records the bench arrangement, including motors, controllers, the custom board and a Nucleo. A still image cannot establish motion, correct wiring, safe power distribution or motor performance. Consult the [verification notes](verification.md) for the separately recorded controller identities and telemetry.

### Demonstration video

[Open/download the original bench video](../evidence/videos/bench-demo-supplied-2026-10-02.mp4) — approximately 20.8 seconds, 3.38 MB.

The clip shows the motors and wiring, followed by the laptop's two-motor G474 keyboard-control interface. A motor label reading 6374 190KV is visible. It documents the demonstration setup, not an independent measurement of CAN payloads, packet latency, calibrated RPM, loaded torque or four-wheel locomotion. Background troubleshooting discussion is visible on the laptop; the clip should not be interpreted as a fault-free endurance run. It is not established to be synchronised with the included 1 October logs.

The video is preserved with its original audio. Playback support varies by GitHub client; use the file's download option if inline playback is unavailable.

## SWD debugging captures — not CAN

The channel identities follow Aidan's identification in the original debugging discussion: **CH1/yellow is SWCLK; CH2/green is SWDIO**. Both channels display DC coupling, 10:1 attenuation and 1 V/div.

<img src="../evidence/images/swd-clock-data-wide.jpeg" alt="SWCLK and SWDIO capture at 50 microseconds per division" width="750">

Wide view at **50 µs/div**. The scope displays CH1 maximum 3.05 V, CH1 minimum −250 mV, CH2 minimum −220 mV and a CH1 frequency reading of 139.3 kHz. These are displayed scope measurements, not independently calibrated values or a guarantee of the programmer's configured clock rate.

<img src="../evidence/images/swd-clock-data-detail.jpeg" alt="SWCLK and SWDIO detail at 10 microseconds per division" width="750">

Detail at **10 µs/div**. The displayed CH1 maximum is 3.01 V; minima are −250 mV for CH1 and −220 mV for CH2. Clock and data transitions are visible, but no SWD transaction is decoded here. Activity alone does not prove that the MCU returned a valid debug response or that its pins are undamaged. The negative minima alone do not establish a hardware damage mechanism; probing and undershoot need separate assessment.

These captures belong to the separate debug-interface investigation. They are not CANH/CANL measurements, UART decoding, or before/after proof of the TCAN3413 solder repair.

## Earlier EasyEDA schematic — design history only

<img src="../hardware/images/schematic-2026-09-04-historical.png" alt="Historical EasyEDA schematic export showing an earlier STM32G474 design" width="900">

This original export has a filename dated **4 September 2026**. It shows STM32G474RET6 with CAN on PB13/PB12, unlike the later STM32G431RBT6 revision documented in this repository. It is included to show design development, **not as the wiring reference for the current board**.

Use the [27 September EasyEDA source exports](../hardware/source) and [hardware notes](../hardware/README.md) for the documented revision. The current [CAN routing audit](../hardware/images/can_routing.png) is reconstructed from that later PCB export; it is not an original EasyEDA screenshot or fabrication output.

## Still needed

- Close-ups of the assembled PCB and the repaired TCAN3413 lead-to-pad joints.
- Annotated, repeatable CANH/CANL measurements before and after repair.
- Independently decoded CAN frames and repeatable payload/sequence tests.
- Loaded and multi-node testing before making robot-level performance claims.
