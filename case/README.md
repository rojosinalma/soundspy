# SoundSpy node enclosure

Two-part case for the carrier PCB rev 1.2 (`pcb/inmp441/soundspy-node.kicad_pcb`) with an ESP32 38-pin DevKit soldered on its pin spacers and the INMP441 disc on tall pins over the ESP32's antenna end.

![assembly](preview/assembly.png)

Outer size: **40.4 × 78.4 × 20.85 mm**, including the corner screw towers (the body is 34.8 × 72.8). The base is 18.85 mm tall and the lid 2 mm.

| File | |
|---|---|
| `soundspy-case.scad` | Parametric source, every dimension is a named variable at the top |
| `stl/soundspy-case-base.stl` | Base, print as-is (floor on the bed) |
| `stl/soundspy-case-lid.stl` | Lid, already flipped: outer face on the bed |
| `stl/soundspy-case-tray.stl` | Test tray: the base's floor, standoffs and outline with 6 mm walls. Printed: the carrier fits |
| `stl/soundspy-case-test_usb.stl` | Test slice: the USB end wall on its side with 3 mm of floor. About 9.5 min on Standard; checks the USB-C cutout height against the real board |

Regenerate after changing a parameter: `./scripts/render_case.sh` (needs the `openscad` CLI, 2021.01 or newer; or set `OPENSCAD` to a container command line such as `docker run --rm -v $PWD:$PWD -w $PWD openscad/openscad:dev openscad`). It runs the fit check first and fails if the case would collide with any board part, **or if anything overhangs the board's drop-in path** (the check that would have caught the first version's corner posts). You can also override values without editing, e.g. `./scripts/render_case.sh -D usb_bottom_tbl=12.5`.

## Hardware

- 2× M2×5 thread-forming (or wood-thread) screws: carrier PCB → the two mic-end standoffs. The soldered ESP32 covers the two USB-end holes, so that end just rests on its standoffs.
- 4× M2×8 screws: lid → corner towers
- Optional: 2 wall screws for the keyholes (head ≤ 7 mm, ≤ 3 mm tall)

## Print

- PLA, no supports, 0.4 mm nozzle. Prototypes print fine at 0.16–0.2 mm layers (base: about 40 min); final parts at a finer quality profile (base: about 46 min).
- Pilot holes are 1.7 mm (`m2_pilot`). If screws are too tight or loose on your printer, adjust that value and re-render.

## Assembly

1. Drop the board in straight, USB end toward the USB cutout, and screw down the two mic-end corners.
2. Lay the lid on with the grille over the mic, then screw it into the four corner towers.

Sound reaches the mic through the lid grille directly above it and the five slots in the mic-end wall at mic height. The case hangs on the keyholes with the mic end up and the USB cable exiting downward.

## Measured on the assembled board (in the test tray)

- USB-C spans 12–15 mm above the table (`usb_bottom_tbl = 12`); its front is flush with the carrier edge (`esp_usb_end_y = 68`)
- Mic disc top 15 mm above the table (`mic_top_tbl = 15`)
- ESP32 57 mm long (`esp_l = 57`)

## Still assumed

- `esp_w = 28`: ESP32 width
- `usb_h = 3.2`: USB-C receptacle height
- `usb_cut_w/h = 13 × 7.5`: sized for the cable's plug overmold, not the receptacle
