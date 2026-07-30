# Changelog

All notable changes to the soundspy project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning Policy

- **MAJOR.MINOR.PATCH** (e.g., 0.8.3)
- **PATCH**: Bug fixes, optimization, logging changes (0.8.2 → 0.8.3)
- **MINOR**: New features, new capabilities (0.8.x → 0.9.0)
- **MAJOR**: Breaking changes, protocol changes, incompatible with dashboard (0.x.x → 1.0.0)

## [Unreleased]

## [1.3.1] - 2026-07-30

### Fixed
- Duplicate chip IDs across boards: now uses lower 4 bytes of EfuseMAC (8-char hex) instead of middle 3 bytes which collided on chips from same batch

### Changed
- Dashboard color palette shifted from blue/purple to green (hardware EQ aesthetic)
- Header uses Share Tech Mono font with phosphor green glow
- Node display names update live on existing cards (not only on card creation)
- Node rename uses inline contenteditable (no browser prompt)
- Edit button (✎) next to node name, audio indicator moved next to mute button
- Mute/unmute button uses ◁ icon, online dot has green glow

## [1.3.0] - 2026-07-30

### Changed
- **BREAKING**: Node ID no longer configured at build time — derived from ESP32 chip ID at runtime (lower 3 bytes of EfuseMAC as 6-char hex)
- Firmware binary is now generic: compile once, flash to any ESP32
- MQTT topics use chip ID: `soundspy/<chip_id>/data` (e.g. `soundspy/a1b2c3/data`)
- Build script no longer takes NODE_ID argument, produces `soundspy_v<version>.bin`
- Deploy script takes chip_id (visible in dashboard) as argument
- NODE_ID removed from `.env`

### Added
- Node name persistence: `data/node_names.json` maps chip IDs to display names
- Auto-naming: new nodes assigned "node-1", "node-2", etc. on first connect
- Rename nodes via double-click in dashboard UI or `POST /api/node/rename`
- Display names shown in node cards, history chart selector, logs
- `data/` volume mounted into dashboard container for state persistence

## [1.2.1] - 2026-07-30

### Added
- Per-node threshold tracking with history chart node selector
- Vertical level meter bar (segmented, with peak hold and zone colors)
- Threshold slider: tick marks every 10dB, snap-to-mark, dynamic zone indicators (▲)
- Slider double-click resets to -20, step=0.5 dBFS
- Overall level display restyled as CRT oscilloscope (phosphor green, vignette)
- Remote logging over MQTT (`soundspy/<node>/log` and `/boot` topics)
- OTA rollback: `esp_ota_mark_app_valid_cancel_rollback()` gates on MQTT connectivity
- Boot report published to MQTT with partition, reset reason, free heap, IP
- Two-stage boot order: WiFi → MQTT → OTA confirm → I2S → WebSocket
- Live logs panel in dashboard: per-node sidebar + app/system tab split
- Deep sleep command (`{"sleep": true}`) for safe power-off
- I2S watchdog stays alive in degraded mode after 3 failed reinits (keeps MQTT)

### Changed
- MQTT buffer increased to 512 bytes
- Boot messages flush with `mqtt.loop()` after publish

## [1.1.0] - 2026-07-30

### Changed
- All firmware config (WiFi, MQTT, WS, NODE_ID) moved to PLACEHOLDER_* tokens
- Version is the only hardcoded value in firmware source
- Build script extracts version from .ino (not .env)
- Build generates `node_firmware.rendered.ino` for Arduino IDE manual flashing

### Removed
- FIRMWARE_VERSION from `.env` (now source-of-truth is the .ino)

## [1.0.0] - 2026-07-30

### Added
- I2S watchdog: auto-reinitializes bus after 5 consecutive -180 dBFS readings, reboots if reinit fails
- Custom confirm modal (replaces browser confirm() dialogs)

### Changed
- Firmware consolidated to single file: `node_firmware/node_firmware.ino`
- Credentials removed from source — all config injected from `.env` at build time
- Threshold input spinner arrows removed (use slider or type directly)
- Build script sed patterns simplified for robustness

### Removed
- Legacy firmware files (`node.ino`, `node_multiband.ino`)
- Hardcoded WiFi/MQTT credentials from firmware source
- Old firmware files purged from git history

## [0.9.3] - 2026-07-30

### Added
- Reboot command via MQTT control channel (`{"reboot": true}`)
- History chart colored zone backgrounds (green/yellow/red)
- Average level line (flat dotted) on history chart with zone-colored styling
- Multi-node color palette for history chart (supports unlimited nodes)
- Knob snapping at 10% increments with 11 notch marks
- Double-click knobs to reset to defaults
- EMA smoothing on overall level display
- Live log scroll pause with Resume button
- GitHub footer link
- Window resize handler for log expansion

### Changed
- Frequency bands realigned for ICS-43434 mic (50 Hz–20 kHz)
- New biquad bandpass coefficients for all 6 bands
- Zone thresholds: Green < -20, Yellow -20 to -10, Red > -10 dBFS
- Default alert threshold: -20 dBFS
- Mic gain range reduced to 0–10x (was 0–20x), default 4x (40%)
- Knob sweep expanded to 300° (was 270°)
- History chart: fixed Y-axis (-80 to 0), normalized X-axis (full width)
- History downsampled to 1 point/sec (was raw ~20Hz)
- Default time range: 1 minute (was 5 minutes)
- Overall level displays as integer (was 1 decimal)
- Wave visualization uses zone colors (was multicolor gradient)
- Threshold slider gradient matches zone boundaries
- Header restyled with gradient title
- Live log renamed, collapsible with proper sizing
- Dashboard container uses volume mounts for live reload
- Flask debug mode with auto-reloader

### Removed
- Latency tracking from log entries and backend

### Fixed
- History chart line not spanning full width
- Knob indicator not aligning with notch marks
- dBFS values below -80 showing as -180 (now clamped)

## [0.9.0] - 2026-07-30

### Changed
- Frequency bands realigned for INMP441 mic (60 Hz–15 kHz)
- Mic gain default reduced to 2x, max to 10x

## [0.8.4] - 2026-07-29

### Added
- `deploy_ota.sh` script for automated OTA deployment
- `init_arduino.sh` script for toolchain setup
- Automated OTA workflow (build → upload → trigger)

## [0.8.3] - 2026-07-29

### Added
- `.env` file support for centralized configuration management
- `.env.example` template file for easy setup
- `build_firmware.sh` script to compile firmware with injected .env values
- Environment variable support in docker-compose.yml
- Firmware output directory (`firmware/`)

### Changed
- Moved sensitive configuration (WiFi, MQTT) to `.env` file
- Updated docker-compose.yml to use environment variables
- Updated .gitignore to exclude .env and .bin files
- Firmware config values now injected at build time from .env

## [0.8.2] - 2026-07-29

### Fixed
- Removed LED_BUILTIN reference causing compilation errors on some ESP32 boards

## [0.8.1] - 2026-07-29

### Changed
- Reduced serial logging spam - only important events logged
- Added `[IMPORTANT]` tag to critical log messages
- Removed 50Hz sensor data from serial output
- Added startup banner with version and node ID
- OTA progress now logged every 10% instead of continuous

### Added
- Cleaner serial monitor output for debugging

## [0.8.0] - 2026-07-29

### Added
- OTA (Over-The-Air) firmware update support via HTTP
- Dashboard firmware upload interface with modal dialog
- Firmware version reporting via MQTT
- Version display on dashboard (per node)
- `/api/ota/upload` endpoint for firmware uploads
- `/api/ota/trigger` endpoint to initiate OTA updates
- `/firmware/<filename>` endpoint to serve firmware files to ESP32

### Changed
- Bumped to MINOR version for new OTA feature
- Updated dashboard UI with "📡 Update" button per node

## [0.7.6] - 2026-07-29

### Added
- Include firmware version in every data message (not just on connect)

## [0.7.5] - 2026-07-29

### Added
- Firmware version reporting via MQTT on connection

## [0.7.0] - 2026-07-29

### Fixed
- **CRITICAL**: Apply mic gain early in signal chain
  - Gain now affects both frequency analysis AND audio streaming
  - Previously gain only affected audio, not frequency readings
  - Setting gain to 0% now stops all processing correctly

### Changed
- Moved gain application before frequency band filtering

## [0.6.0] - 2026-07-29

### Added
- Real-time audio streaming via WebSocket
- Raw WebSocket endpoint (`/ws/audio`) for ESP32 audio streaming
- Audio playback controls on dashboard (mute/unmute per node)
- Browser volume control (separate from mic gain)
- Web Audio API integration with scheduled buffer playback

## [0.5.0] - 2026-07-29

### Added
- Multi-band frequency analysis (6 bands)
- Bands: sub-bass (20-60Hz), bass (60-250Hz), low-mid (250-500Hz), mid (500-2kHz), high-mid (2k-4kHz), high (4k-8kHz)
- Cascaded Butterworth biquad bandpass filters
- Real-time frequency visualization on dashboard
- EQ-style spectrum display (bars and wave modes)
- Professional audio meter styling with color-coded levels
- Peak hold markers with fade effect

### Changed
- Increased publish rate to 50Hz for responsive readings
- Expanded MQTT payload to include all frequency bands

## [0.4.0] - 2026-07-29

### Added
- Web dashboard with Flask + SocketIO
- Real-time WebSocket updates (replaced SSE)
- Remote mic gain control via MQTT
- Rotary knob UI for gain adjustment
- Historical chart with Chart.js (5-minute rolling window)
- Live data log with sequence numbers and latency display

### Changed
- Switched from Server-Sent Events to WebSocket for lower latency
- Improved dashboard rendering performance

## [0.3.0] - 2026-07-29

### Added
- Docker-based backend services
- Mosquitto MQTT broker
- ntfy notification service
- Threshold monitoring service
- Per-node cooldown for alerts

## [0.2.0] - 2026-07-29

### Added
- Basic ESP32 firmware with I2S audio sampling
- MQTT publishing of dBFS levels
- Overall level and bass-band measurements

## [0.1.0] - 2026-07-29

### Added
- Initial project structure
- Basic README documentation
- Hardware wiring documentation
