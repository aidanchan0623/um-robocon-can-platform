# UM Robocon CAN Platform

An early **UM Robocon Team** control-board prototype combining an onboard MCU with PWM/encoder interfaces and CAN communication between nodes. This repository collects the design, external-controller CAN tests, one-/two-motor VESC firmware and hardware debugging toward distributed BLDC robot control.

Two separate solder faults shaped our bring-up process: intermittent TCAN3413 CAN lead contact, and an inadequately soldered G431 SWDIO lead. I traced the paths with a multimeter and oscilloscope; the [case studies and assembly checklist](docs/debugging.md) distinguish measured results from reported recovery.

**Test scope:** external Nucleos validated the custom transceiver path at 1 Mbit/s; **the onboard G431 was not the CAN controller under test**. Two unloaded BLDCs were demonstrated separately at 250 kbit/s. Onboard CAN/PWM/encoder operation, four-wheel locomotion, loaded performance and EMC remain unvalidated.

<img src="hardware/images/photos/candrive-v1-bare-pcb.jpeg" alt="Unpopulated CANDrive v1 PCB held in hand" width="600">

*The team's CANDrive v1 bare PCB before component assembly.*

Start with the [hardware notes](hardware/README.md), [build instructions](docs/build-and-use.md), [debugging case study](docs/debugging.md), or [media gallery](docs/media-gallery.md).

## Design

The board has two complementary parts:

- **Local motor control:** the STM32G431RBT6 is intended to run control logic, command an external motor driver through PWM and read encoder feedback.
- **Communication between nodes:** the TCAN3413 connects the MCU's CAN controller to CANH/CANL, so controller nodes can exchange commands and feedback. Each node needs a suitable CAN interface and compatible bus settings. CAN1 and CAN2 are connections to the same bus.

The motor power stage is external. Our BLDC bench work uses VESC-compatible ESCs. An external-MCU CAN header lets a Nucleo use the transceiver while the onboard MCU is absent or electrically isolated, which helped me test the network separately from the local controller.

Original ping/reply and VESC demonstrations use **250 kbit/s**. The separate **1 Mbit/s** diagnostic uses eight-byte requests/echoes on IDs `0x601`/`0x602`; it is not motor-control firmware. [Firmware provenance](docs/firmware-provenance.md) maps each snapshot to code and available image identities; release [v0.2.0-bench-validation](https://github.com/aidanchan0623/um-robocon-can-platform/releases/tag/v0.2.0-bench-validation) freezes the evidence.

```text
MCU-to-MCU test:
G474 → custom transceiver board ═ CANH/CANL ═ custom transceiver board ← F303

Dual-motor test:
Laptop → G474 → custom transceiver board ═ CAN bus ═ VESC ID 1 + VESC ID 2
```

All nodes need a common signal-ground reference. MCU TX connects to transceiver TXD; RX connects to RXD. These are not crossed as UART signals are.

<img src="hardware/images/can_routing.png" alt="CAN signal-path diagram reconstructed from the September 27 PCB export" width="520">

*I reconstructed this signal-path diagram from the PCB export to explain the routing. I use the original exports as the fabrication reference.* See [hardware notes](hardware/README.md) and the original [EasyEDA exports](hardware/source).

## PCB design and trade-offs

<img src="hardware/images/candrive-full-pcb-easyeda.jpg" alt="Complete CANDrive v1 PCB opened in EasyEDA, showing MCU, CAN bus interface and motor I/O placement" width="850">

*Actual EasyEDA view of our September 27 PCB export. I hid copper pours for trace visibility.*

Keeping CANH and CANL together was one of my main design challenges. I had to balance similar path lengths and fewer layer changes against component placement and access to the connectors.

- I kept both CAN headers in the same orientation and pin order to reduce wiring confusion, accepting a less direct routing path as the trade-off.
- I iterated the CMC placement and brought its bypass resistors closer to the pads, reducing detours and long branches.
- I placed the TVS near the bus connections and worked on its ground path. The optional CMC adds a filtering option, although my bench setup used separate CANH/CANL bypass resistors.

**Note:** I have not measured the effect of the remaining length mismatch or vias, or verified controlled differential impedance and EMC. The communication fault I traced came from the solder contacts at the transceiver leads.

Read my [board purpose and PCB design decisions](docs/pcb-design-decisions.md) for the placement iterations, routing compromises and next tests.

## Key hardware

| Part | Role |
| --- | --- |
| Custom CAN-Board-V1 | Transceiver, protection, selectable termination, MCU and I/O interfaces |
| TI TCAN3413DR | 3.3 V CAN transceiver |
| Nexperia PESD2CANFD27V-T | Bus ESD protection |
| Two 62 Ω resistors and split capacitor | Selectable split termination, approximately 124 Ω per board |
| R1 and R10, 0 Ω | Separate CANH and CANL bypasses while the CMC is omitted |
| NUCLEO-G474RE / NUCLEO-F303RE | External CAN test controllers |
| Flipsky 6374 190KV motors | BLDC bench-test motors |
| Mini 6.7 and replacement FS75100 | Successful final dual-test ESC pair |

I list the main hardware here; the source exports contain the detailed values and footprints. Note: I used a **4S LiPo** for the dual-motor bench. I have not tested a 6S robot power system.

## Assembly and debugging

I traced power, continuity, firmware, loopback, external signals and termination. Unpowered CANH–CANL resistance varied from approximately **32 kΩ to 60 Ω with probe pressure**; transceiver lead-to-pad rework restored communication.

This was poor contact between each CAN lead and its own pad, not a short joining CANH to CANL. The separate G431 SWDIO repair has reported flash success; its verify log, UART capture, joint photo and measured continuity remain pending. Follow the [assembly checklist](docs/assembly-checklist.md) before bring-up.

## Usage

Choose one firmware application at a time. Building does not flash the MCU, and none of the repository's build tools contacts hardware.

| Application | Target | Purpose |
| --- | --- | --- |
| [g431-uart](firmware/g431-uart) | Custom STM32G431RBT6 | Repeated USART3 output on PC10 at 9600 baud |
| [g474-can-ping](firmware/g474-can-ping) | NUCLEO-G474RE | Standard-ID `0x123` ping every 500 ms |
| [f303-can-reply](firmware/f303-can-reply) | NUCLEO-F303RE | Reply on standard ID `0x124` |
| [CAN1M diagnostic overlays](evidence/can-1mbit-2026-10-05/REPRODUCTION.md) | G474 + F303 | 1 Mbit/s, IDs `0x601`/`0x602`, eight-byte integrity test |
| [g474-vesc-single](firmware/g474-vesc-single) | NUCLEO-G474RE | One VESC, keyboard bench control |
| [g474-vesc-dual](firmware/g474-vesc-dual) | NUCLEO-G474RE | Two VESCs, shared speed request and feedback checks |

Follow [build and use](docs/build-and-use.md) before programming or powering motors. [Protocol notes](docs/protocol.md) explain the IDs, payloads and diagnostic counters.

Motor firmware starts disarmed. Key release requests **zero current and coast**, not active braking. Software timeouts are not a physical emergency stop. Mount motors securely, keep shafts/wheels clear, configure each ESC for its own motor and battery, and provide a physical means of removing motor power.

## What I tested and what comes next

| Check | Recorded result | Scope |
| --- | --- | --- |
| 1 Mbit/s integrity + endurance | **5,330,951 eight-byte pairs**, 16 stages including a 30-minute soak; zero recorded run integrity/controller faults | External Nucleo/transceiver path; [raw evidence](evidence/README.md) |
| Soak throughput / round trip | About **2,327 pairs/s**; **1.724 ms** max application RTT; **1,804 pacing misses** | Scheduling misses, not lost frames; derived bus load about **52–63%** |
| Two-BLDC demonstration | Direction/speed requests, approximately 50 Hz feedback; 42 startup logic checks | Separate unloaded 250 kbit/s motor test |
| G431 SWDIO recovery | Flash success reported after solder repair | Verify/UART/photo/continuity evidence pending |

See [verification](docs/verification.md) for methods, internal-oscillator risk and limits. CAN waveforms, onboard MCU functions, noisy multi-node testing and loaded locomotion remain future work.

## Bench demonstration

<a href="evidence/videos/bench-demo-supplied-2026-10-02.mp4"><img src="hardware/images/photos/dual-motor-bench.jpeg" alt="Two-motor bench setup with controllers, custom PCB and Nucleo" width="400"></a>

*Two-motor bench arrangement. [Open/download the demonstration video](evidence/videos/bench-demo-supplied-2026-10-02.mp4) (20.8 seconds).* This shows the workflow; calibrated motor measurements remain pending.

The [media gallery](docs/media-gallery.md) includes the PCB and bench photographs, SWCLK/SWDIO debugging captures, and a clearly labelled earlier EasyEDA schematic. Note: my scope photographs show **SWCLK/SWDIO** during the debug-interface investigation. I have not included CANH/CANL captures yet.

## To do

- [x] Add supplied bare-PCB and bench photos, SWD captures and demonstration video.
- [ ] Add assembled-board close-ups, solder-joint repair photos and decoded CAN captures.
- [ ] Record repeatable power-off continuity tests after solder rework.
- [ ] Measure termination on the final mixed-ESC bus.
- [ ] Validate PWM and encoder channels on the assembled PCB.
- [ ] Add host-side unit tests for packet encoding/decoding, command validation, timeouts and reversal logic, then automate them in CI.
- [ ] Run frame-sequence, command/feedback and disconnect tests with a CAN analyser.
- [ ] Test four independently addressed ESCs before claiming four-wheel operation.
- [ ] Validate wheel encoders, loaded low-speed control, thermal behavior and power distribution.
- [ ] Improve bus pairing/stubs and perform EMC review for the next board revision.
- [ ] Agree on explicit hardware/software licenses with the contributors.

## Credits

**Chan Zhi Hong (Aidan) — UM Robocon Team:** CAN functionality and board requirements; most hardware diagnosis, manual measurements and debugging.

**Rui Leong — UM Robocon Team:** STM32 section design, PWM and encoder functionality.

**Assembly and soldering:** Rui Leong and I shared this work.

I used AI assistance for firmware development, documentation and troubleshooting suggestions. Rui Leong and I carried out the physical probing, measurements, soldering and rework. I present this as our collaborative prototype and distinguish my work from Rui Leong’s contributions.

The clear hardware-project presentation in [bjpirt/shutter-tester](https://github.com/bjpirt/shutter-tester) inspired this repository's organisation; its code and prose were not copied.

No project-wide license has been selected for the team's original material; publication is not a claim that the whole project is open-source licensed. Existing third-party notices remain in place; see [attribution and licensing](THIRD_PARTY_NOTICES.md).
