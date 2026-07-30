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

The INMP441 module mounts on the `soundspy-node` carrier board (`pcb/soundspy-node.kicad_pcb`) via the 2x3 pin header. The carrier board has:

- A 3mm through-hole aligned with the mic's sound port
- 100nF decoupling cap (C1) on the 3V3 line near the connector
- Board outline: 30×68mm with USB-C notch at the bottom

## Notes

- LR pin must be tied to GND for left channel selection — connected to GND net on the carrier
- Route LR to GND during PCB layout in KiCad
- The carrier PCB is unrouted — open `soundspy-node.kicad_pcb` in KiCad and use the ratsnest to complete routing
