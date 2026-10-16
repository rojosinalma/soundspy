# Hardware

## Components per node

- ESP32 development board, 38-pin DevKit (ESP32-WROOM-32, 4 MB flash, CP2102 USB-UART)
- I2S MEMS microphone: INMP441 on the common 14 mm round breakout, or an ICS-43434 breakout
- Optional: the carrier PCB in `pcb/inmp441/` and the printed enclosure in `case/`

## Wiring (I2S mic → ESP32)

| Mic pin | ESP32 GPIO | Signal |
|---------|------------|--------|
| VDD     | 3.3V       | Power (never 5 V) |
| GND     | GND        | Ground |
| SD      | GPIO 32    | Serial data |
| WS      | GPIO 25    | Word select (LRCLK) |
| SCK     | GPIO 33    | Bit clock |
| L/R     | GND        | Channel select: GND = left slot |

The pins are fixed in `firmware/audio.cpp` (`PIN_SCK`, `PIN_WS`, `PIN_SD`). The firmware reads the left slot by default; if your mic has L/R tied high, set the node's `slot` setting to `1` instead of rewiring (see [firmware.md](firmware.md)).

The INMP441 breakout has a 2×3 header (2.54 mm pitch, 7.62 mm between rows):

```
  GND   VDD   SD
   ●     ●     ●
  ( microphone  )
   ●     ●     ●
  LR    WS    SCK
```

Signal notes:

- Capture is 44.1 kHz, 32-bit slots, 24-bit samples shifted down by 8 bits.
- Keep the mic leads short; a 100 nF capacitor across VDD/GND near the mic helps on breadboards. The carrier PCB has it as C1.

## Carrier PCB (`pcb/inmp441/`)

KiCad project `soundspy-node`: a 30 × 68 mm board that takes the 38-pin DevKit on two 1×19 socket rows and the INMP441 module on a 2×3 header, with a USB-C notch on the bottom edge for the case and four M2 mounting holes. The module sits on the component side with the sound port facing away from the board; sound enters through the enclosure lid. Pinout, dimensions and routing notes are in `pcb/inmp441/DESIGN.md`; the `publish-pcb` workflow zips the project and publishes a `pcb-inmp441-v<version>` release whenever `pcb/inmp441/VERSION` changes.

## Enclosure (`case/`)

Parametric OpenSCAD designs for the carrier board: a two-part screw case (`soundspy-case.scad`) and the snap-fit capsule (`soundspy-capsule.scad`, with the production plates under `case/v5/`). Printed STLs and preview renders are committed next to the sources. `case/README.md` lists the parts, screws, print settings and the measured board dimensions the models are built around; `scripts/render_case.sh` re-renders everything with the OpenSCAD CLI after a parameter change and runs a collision check against the board model first.
