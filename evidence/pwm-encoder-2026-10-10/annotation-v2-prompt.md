# Annotation revision 2

Created with the built-in image editor. User clarified that the external transceiver is a CANDrive board without a local MCU; the encoder leader should land on the coloured wire bundle.

Use case: precise-object-edit / text-localization.
Input image is the edit target: an annotated real bench photograph on a 1536 × 1024 canvas.
Make exactly TWO annotation corrections, preserving the photograph, all hardware, wire colors/positions, layout, fonts, all other labels and leader lines unchanged:
1. Correct the green leader for "Encoder A / B feedback". Remove its current endpoint dot at approximately (839,504), where it ambiguously points at a black cable. Move the endpoint onto the clearly visible THIN MULTICOLOURED encoder bundle (blue, green, yellow, red strands) between the motor encoder PCB and the G431, at approximately (879,552) in this input canvas, just left of the small green encoder PCB attached to the motor. The colored wires curve below the thick BLACK motor lead; point at the colored strands themselves, NOT at that black lead, NOT the motor casing, NOT the white tape. Keep the green label where it is; reroute its thin green leader downward to the coloured wire bundle so the exact target is unambiguous.
2. Replace the bottom-left blue callout "External CAN transceiver board" with this exact TWO-LINE label:
"CANDrive board"
"External transceiver · No local MCU"
Keep its existing blue endpoint on the small black CANDrive PCB at lower left. It is our CANDrive board used as the Nucleo's transceiver, with the local MCU not populated. Preserve all hardware in the photograph; do not add or remove a chip. Slightly enlarge this label box if needed for readability, keeping it outside the photo.
No other changes. Preserve the original bench photograph faithfully and do not invent wire connections.
