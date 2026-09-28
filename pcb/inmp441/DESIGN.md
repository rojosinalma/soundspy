# INMP441 Mic Module

Circular breakout board with INMP441 MEMS I2S microphone.

## Module Specs

- **Dimensions:** 14mm diameter, 3mm height
- **Interface:** I2S
- **Header:** 2x3, 2.54mm column pitch, 7.62mm row separation
- **Drill:** 0.762mm, pad diameter 1.524mm
- **Sound port hole:** 3mm center drill

## Pin Layout

```
  GND   VDD   SD
   ●     ●     ●
  ( microphone  )
   ●     ●     ●
  LR    WS    SCK
```

| Pin | Signal | ESP32 GPIO |
|-----|--------|-----------|
| VDD | 3.3V   | 3.3V |
| GND | Ground | GND |
| SD  | I2S Data out | GPIO32 |
| WS  | I2S Word Select | GPIO25 |
| SCK | I2S Clock | GPIO33 |
| LR  | Channel select | GND (left channel) |

## Reference

- KiCad schematic symbol and footprint (legacy KiCad 4/5 format):
  https://github.com/barafael/inmp441-breakout-kicad

## Carrier Board Integration

The INMP441 module mounts on the `soundspy-node` carrier board (`pcb/inmp441/soundspy-node.kicad_pcb`) via the 2x3 pin header. As printed (rev 1.2 title block):

- Board outline: 30×68mm, 1.6mm thick, USB-C notch 11×4mm centred on the bottom edge (x 9.5–20.5, y 64–68)
- 4x M2 mounting holes (Ø2.2) at (3,3), (27,3), (3,65), (27,65)
- Mic header centred at (15,9). Module sits on the **front (component) side, sound port facing up/away** from the carrier — no sound-port hole in the PCB, sound enters through the case lid
- C1: 100nF THT disc cap (5mm pitch) at x=21.5, y=6–11, on 3V3/GND near the mic
- ESP32 38-pin DevKit: two 1x19 rows at x=2.3 and x=27.7, from y=16 to y=61.72, USB end at the notch. The dev board's antenna end overhangs the mic, so the ESP32 must sit on female socket strips above the mic module
- Fully routed: tracks on F.Cu, GND pour on B.Cu

## Notes

- LR pin tied to GND for left channel selection
- Enclosure for this board: `case/` (OpenSCAD, parametric)
