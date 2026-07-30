# Hardware Wiring

## Components (per node)

- ESP32 development board
- ICS-43434 or INMP441 I2S MEMS microphone

The ICS-43434 is a bottom-port mic. A custom KiCad breakout PCB is available in the `pcb/` directory — a 15×12 mm 2-layer board with a VDD decoupling cap and a 5-pin 2.54 mm header that mates directly to an ESP32 DevKit. See `pcb/DESIGN.md` for the full BOM and assembly notes.

The INMP441 is a top-port alternative that can be wired directly to an ESP32 using the same GPIO assignments.

## I2S Pin Mapping

| Mic Pin | ESP32 GPIO | Signal              |
|---------|------------|---------------------|
| VDD     | 3.3V       | Power               |
| GND     | GND        | Ground              |
| L/R     | GND        | Channel select (left) |
| WS      | GPIO 25    | Word Select (LRCLK) |
| SD      | GPIO 32    | Serial Data         |
| SCK     | GPIO 33    | Bit Clock           |

## Notes

- L/R tied to GND selects the left channel, matching `I2S_CHANNEL_FMT_ONLY_LEFT` in firmware.
- The firmware samples at 44.1 kHz, 32-bit, shifted right by 8 bits to recover the 24-bit value from the ICS-43434.
- For the ICS-43434 breakout PCB: place the 100 nF VDD decoupling cap as close to the mic as possible (< 1 mm). The sound port faces down through the PCB, so the mic must be mounted with the port hole aligned.
- For the INMP441: same GPIO assignments apply. The INMP441 outputs valid 24-bit data in the upper bits; the same `>> 8` shift in firmware handles both mics correctly.
- ESP32 DevKit 3.3V rail is sufficient for both mics. Do not connect mic VDD to 5V.

## Custom PCB

The `pcb/soundspy-mic-breakout.kicad_pcb` project contains a minimal breakout designed to sit alongside an ESP32 DevKit. Open in KiCad 7+, run DRC, then export Gerbers from File → Fabrication Outputs. The board is simple enough for any PCB fab (JLCPCB, PCBWay, OSHPark).
