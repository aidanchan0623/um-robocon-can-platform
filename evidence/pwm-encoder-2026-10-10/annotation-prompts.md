# Bench photograph annotation prompts

Generated with the built-in image editor. The original photograph is preserved separately; annotations are descriptive context, not a verified schematic.

## Initial annotation

Use case: precise-object-edit / scientific-educational annotation.
Input image: edit target, the supplied real 810 x 1080 portrait bench photograph.
Create a professional annotated bench-setup photograph for a programming-team handover and a future GitHub README. Preserve the original photograph, its entire field of view, camera perspective, every board, wire, connector, color and physical object unchanged. Do not redraw, simplify, relocate, invent or remove hardware. Add only a white outer canvas, readable text callouts and thin colored leader lines with small endpoint dots. Keep all labels outside the photograph where possible; do not obscure circuit boards or wires. Use a roomy landscape layout with the intact portrait photo centered and wide left/right annotation gutters. Crisp modern sans-serif type, dark navy text, restrained blue for CAN, orange for power, green for encoder, violet for PWM. Render the exact labels below legibly, one instance per label, and point precisely to the stated visible object using the ORIGINAL PHOTO pixel coordinates (not final canvas coordinates).
Title: "CANDrive motor control bench"
Subtitle: "PC → F303 → CAN → G431 → PWM motor driver · Encoder feedback returns over CAN"

Callouts with target locations in the original photograph:
1. "Bench DC power supply" -> large black vented box upper left, center (225,175). Do NOT label this unit's output voltage because its setting is not visible.
2. "Battery pack" -> yellow wrapped battery upper right, center (635,392). Do NOT invent battery voltage or cell count.
3. "5 V logic power wiring" / second line "Red / black supply leads" -> red/black pair entering the small black board bottom left, near (237,760). This describes the board-supply connection, not the battery.
4. "External CAN transceiver board" -> small black rectangular PCB bottom left, center (300,795). Do NOT call this populated board a second G431 controller.
5. "NUCLEO F303" / second line "PC interface and CAN bridge" -> white ST development board lower right, center (480,840).
6. "MCU CAN TX / RX wires" / second line "F303 ↔ transceiver" -> short white/black curved signal pair between the Nucleo and external transceiver, around (377,776). These are logic-side CAN signals, not CANH/CANL.
7. "CANH / CANL bus" / second line "Yellow / black twisted pair" -> the long twisted yellow/black pair between external transceiver at (310,757) and upper controller at (407,604), point to the clear lower middle portion (337,703). Do NOT point at USB or red/black power wires.
8. "Custom G431 CANDrive board" -> black controller PCB at center-right, center (478,605), above the red motor driver.
9. "Motor driver" / second line "PWM1 / PWM2 control from G431" -> the red PCB visible directly beneath the black G431 board, exposed strip near (467,637). Do NOT point at the loose pink ribbon as a confirmed connection.
10. "Encoder A / B feedback" -> the thin multicolored motor-encoder wire bundle running from the small encoder PCB on motor left end toward the G431, near (536,558). Distinguish these from thick red/black motor power leads.
11. "IG42 geared DC motor" -> black cylindrical mounted motor on right, center (710,567).
12. "USB to PC" -> black USB lead leaving bottom of Nucleo, near (454,946).
The brown perfboard and screw-terminal block may stay unlabeled because their exact circuit functions are not established. Do not create additional voltage labels, terminal pinouts, schematic connections, claims of measured accuracy, or inferred wire polarity. Leader lines must not imply electrical connections that are not shown. Keep layout uncluttered, labels readable and arrow endpoints unambiguous. Add a small footer "Annotated photograph · Wiring context, not a schematic". No watermark or other text.

## Targeted correction

undefined
