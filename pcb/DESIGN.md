# SoundSpy Mic Breakout PCB

Minimal breakout adapter: ICS-43434 MEMS mic → 5-pin header for ESP32 DevKit.

## Board specs
- Size: 15mm x 12mm, 2-layer, 1.6mm FR4
- Back copper: solid GND fill (EMI shielding for mic)
- Sound port: bottom-port (hole through PCB under mic)

## Schematic

```
  ESP32 DevKit          Breakout PCB
  ───────────          ─────────────────────────
  3V3  ──────── J1.1 ──── C1 ──── U1.VDD
  GND  ──────── J1.2 ──── C1 ──── U1.GND, U1.L/R
  GPIO25 ────── J1.3 ──────────── U1.WS
  GPIO32 ────── J1.4 ──────────── U1.SD
  GPIO33 ────── J1.5 ──────────── U1.SCK
```

## BOM

| Ref | Part         | Package      | Notes                    |
|-----|--------------|--------------|--------------------------|
| U1  | ICS-43434    | LGA-6 (3.5x2.65mm) | Bottom-port I2S MEMS mic |
| C1  | 100nF MLCC   | 0402         | VDD decoupling, place close to U1 |
| J1  | Pin header 1x5 | 2.54mm pitch | Solders to ESP32 DevKit pins |

## Pin mapping (firmware match)

| Header Pin | ESP32 GPIO | ICS-43434 Pin | Signal |
|-----------|------------|---------------|--------|
| 1         | 3V3        | VDD (5)       | Power  |
| 2         | GND        | GND (3), L/R (4) | Ground + left select |
| 3         | GPIO 25    | WS (1)        | Word Select (LRCLK) |
| 4         | GPIO 32    | SD (6)        | Serial Data |
| 5         | GPIO 33    | SCK (2)       | Bit Clock |

## Assembly notes
- ICS-43434 is a bottom-port mic: sound hole in PCB must align with mic port
- L/R pin tied to GND = left channel (matches `I2S_CHANNEL_FMT_ONLY_LEFT` in firmware)
- C1 must be as close to VDD/GND pins as possible (< 1mm)
- Reflow solder recommended for U1 and C1 (0402 is small for hand soldering)
- M2 mounting hole for enclosure attachment

## Fabrication
Open `soundspy-mic-breakout.kicad_pcb` in KiCad 7+, run DRC, then export Gerbers from File → Fabrication Outputs.
