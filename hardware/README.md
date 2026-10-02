# CAN-Board-V1 hardware

The `source` folder contains the team's EasyEDA Standard schematic and PCB JSON exports dated 27 September 2026. Open the corresponding JSON through EasyEDA's local-file import/open workflow. They are source-design snapshots, **not production Gerbers**. Re-run schematic checks, PCB DRC and manufacturing review before fabricating.

The image in `images/can_routing.png` is a net-coloured audit reconstructed from that PCB export. It does not certify assembly, all copper clearances or manufacturing output.

## External CAN interface

| EX_MCU_CAN pin | PCB net | Connection |
| --- | --- | --- |
| 1 | CAN_TX | External MCU TX → TCAN3413 pin 1 TXD |
| 2 | CAN_RX | External MCU RX ← TCAN3413 pin 4 RXD |
| 3 | GND | Common signal ground |

U1 pin 3 VCC and pin 5 VIO use 3.3 V; pin 2 is ground and pin 8 STB is held low for normal operation. The header does **not** supply power to the transceiver board. Its board power input supplies the regulator separately.

The onboard G431 PA12/PA11 share these TX/RX nets. Remove or electrically isolate that MCU before using an external Nucleo. Leaving it unpowered is not sufficient isolation: signal pins can load the interface or back-power it.

## CAN bus path

U1 pin 7 is CANH, pin 6 is CANL. CAN1/CAN2 expose parallel H/L connections: pin 1 H and pin 2 L. Those two-pin connectors do not provide the common ground, which needs a separate connection.

In the tested CMC-omitted arrangement, **R1 bridges the CANH path and R10 bridges the CANL path**, each at 0 Ω. Never bridge H directly to L. This omits the choke's common-mode filtering; successful bench operation is not an EMC qualification.

Both termination jumpers close the split network: 62 Ω + 62 Ω, with a 4.7 nF midpoint-to-ground capacitor. Two such endpoint boards measure approximately 62 Ω across the assembled, unpowered bus. Two nominal 120 Ω endpoints instead give approximately 60 Ω. Check actual values and instrument tolerance rather than expecting an exact universal reading.

Only the two physical cable ends should be terminated. If the custom board is a middle node between two terminated ESCs, remove both board termination jumpers. Verify each ESC's resistance with all supplies and USB power removed; do not assume its built-in termination or modify unidentified resistors.

## UART naming

The UART header names use the adapter's perspective: header pin 2 (labelled RX / CP2102_RX) carries MCU PC10 TX through R3; header pin 1 (labelled TX / CP2102_TX) feeds MCU PC11 RX through R2. Pin 3 is GND. Confirm numbering and continuity on the physical board before wiring. Use a 3.3 V logic UART adapter, not RS-232 or an unverified 5 V TX output. For transmit-only scope/terminal tests, MCU RX can remain disconnected.

## Review limits

The CAN net/pin mapping and inspected routing support the intended external-controller path. That is not enough to say the entire design is fault-free: assembled contacts, uninspected fabrication details, EMC, fault tolerance, PWM and encoder operation require further validation. The poor CAN lead solder contact was established by the team's physical investigation, not by CAD alone.

Design references: [TI TCAN3413 datasheet](https://www.ti.com/lit/ds/symlink/tcan3413.pdf) and [Nexperia PESD2CANFD27V-T datasheet](https://assets.nexperia.com/documents/data-sheet/PESD2CANFD27V-T.pdf). The team reports consulting the CMC's own datasheet as well; the choke was omitted in the bench arrangement documented here.
