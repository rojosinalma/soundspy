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
