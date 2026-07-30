# soundspy — Multi-Node Sound Monitoring System

Real-time multi-band frequency analysis and audio monitoring system for tracking sound levels across multiple locations. Designed for monitoring when audio production (studio monitors, instruments) might be disturbing neighbors through shared walls.

## Quick Start

**Initial configuration:**
1. Copy `.env.example` to `.env`: `cp .env.example .env`
2. Edit `.env` with your WiFi credentials, MQTT host, and other settings
3. **Never commit `.env` to git** — it contains sensitive credentials

**Hardware setup (per node):**
1. Wire I2S mic (INMP441 or ICS-43434) to ESP32 — see [wiring table](#hardware-wiring)
2. Build and flash firmware (see [Firmware Setup](#firmware-setup))
3. Repeat for each node (change `NODE_ID` parameter when building)

**Backend setup:**
1. On your server: `cd soundspy && docker-compose up -d`
2. Open dashboard: `http://<server-ip>:8091`
3. Subscribe to alerts: `http://<server-ip>:8090/soundspy`

**Using the system:**
1. Monitor real-time levels and frequency bands on the web dashboard
2. Adjust mic gain (0-100%) and browser volume remotely via dashboard knobs
3. Listen to live audio from any node
4. Update firmware via OTA without touching the device

## Architecture

**Hardware:** Scalable ESP32-based nodes, each with an I2S microphone (INMP441 or ICS-43434 — pin-compatible)

**Per-node processing:**
- Samples audio at 44.1kHz via I2S
- Real-time 6-band frequency analysis using cascaded Butterworth biquad filters:
  - **Sub-bass:** 20-60 Hz (wall resonance band)
  - **Bass:** 60-250 Hz (bass guitar fundamentals)
  - **Low-mid:** 250-500 Hz
  - **Mid:** 500-2kHz (presence, vocals)
  - **High-mid:** 2k-4kHz (clarity)
  - **High:** 4k-8kHz (air, cymbals)
- Computes overall RMS dBFS level
- Publishes sensor data at 50Hz via MQTT
- Streams live audio via WebSocket
- Remote-controllable gain (affects both analysis and audio)
- OTA (Over-The-Air) firmware updates

**Backend services (Docker stack):**
- **Mosquitto** — MQTT broker (port 1883)
- **Dashboard** — Flask + SocketIO web interface (port 8091)
  - Real-time frequency visualization (bars or wave mode)
  - Live audio playback with per-node mute/unmute
  - Historical charts (real-time to 1 hour)
  - OTA firmware upload interface
  - Remote gain control via rotary knobs
- **ntfy** — Push notification service (port 8090)
- **threshold_monitor.py** — Alert service with per-node cooldown

**MQTT topic structure:**
```
soundspy/<node_id>/data      # Sensor readings (50Hz)
soundspy/<node_id>/control   # Control commands (gain, OTA)
soundspy/<node_id>/version   # Firmware version
```

**Data payload example:**
```json
{
  "node": "wall1",
  "seq": 1234,
  "ts": 45000,
  "firmware": "0.8.2",
  "overall_dbfs": -32.5,
  "bands": {
    "sub_bass": -45.2,
    "bass": -38.1,
    "low_mid": -42.7,
    "mid": -35.3,
    "high_mid": -50.1,
    "high": -55.8
  }
}
```

## Hardware Wiring

**I2S Microphone pinout (INMP441 / ICS-43434 — identical):**

| Mic Pin | ESP32 GPIO | Function              |
|---------|------------|-----------------------|
| VDD     | 3.3V       | Power                 |
| GND     | GND        | Ground                |
| SD      | GPIO32     | I2S data in           |
| WS      | GPIO25     | I2S word select / LR  |
| SCK     | GPIO33     | I2S bit clock         |
| L/R     | GND        | Left channel select   |

**Notes:**
- Tie L/R to GND for left channel
- All nodes use identical wiring
- INMP441 and ICS-43434 are pin-compatible — swap mics without changing code
- Place ESP32 on insulating surface to avoid electrical noise (anti-static bag works well)

## Firmware Setup

### 1. Install dependencies

**Arduino CLI (recommended for automated builds):**
```bash
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
arduino-cli core install esp32:esp32
arduino-cli lib install PubSubClient WebSockets ArduinoJson
```

**Arduino IDE (manual builds):**
- Install ESP32 board support (Espressif Systems v3.x+)
- Install libraries via Library Manager:
  - `PubSubClient` (MQTT client)
  - `WebSocketsClient` (for audio streaming)
  - `ArduinoJson` (for JSON parsing)
  - `HTTPUpdate` (for OTA updates)
  - Built-in: `WiFi`, `driver/i2s`, `HTTPClient`, `base64`

### 2. Configure environment
Edit `.env` file with your settings (created from `.env.example`):

```bash
# WiFi Configuration
WIFI_SSID=your_wifi_ssid_here
WIFI_PASSWORD=your_wifi_password_here

# MQTT Broker (use your server's IP)
MQTT_HOST=192.168.1.100
MQTT_PORT=1883

# WebSocket Server (usually same as MQTT host)
WS_HOST=192.168.1.100
WS_PORT=8091

# Firmware Configuration
FIRMWARE_VERSION=0.8.3
NODE_PREFIX=node              # Prefix for auto-generated node names
DEFAULT_NODE_ID=node1         # Default when no argument provided
```

### 3. Build firmware (automated with .env injection)

**Option A: Using build script (recommended)**
```bash
# Build with numeric suffix (uses NODE_PREFIX from .env)
./scripts/build_firmware.sh 1    # -> node1
./scripts/build_firmware.sh 2    # -> node2
./scripts/build_firmware.sh 3    # -> node3

# Build with custom name (overrides prefix)
./scripts/build_firmware.sh bedroom
./scripts/build_firmware.sh studio
./scripts/build_firmware.sh wall1

# Use default node from .env
./scripts/build_firmware.sh      # -> node1

# Output: builds/soundspy_node1_v0.8.3.bin
```

The build script:
- Reads configuration from `.env`
- Injects values into firmware source
- Compiles with arduino-cli
- Outputs ready-to-flash `.bin` file

**Option B: Manual build in Arduino IDE**
1. Open `node_firmware/node_firmware.ino`
2. Manually edit the config section with your values
3. Click **Upload** or **Sketch → Export Compiled Binary**

### 4. Initial flash (USB - required once per node)
```bash
# Upload via USB
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 --input-file builds/soundspy_node1_v0.8.3.bin

# Or use Arduino IDE Upload button
```

Open Serial Monitor (115200 baud) to verify connection and watch for `[IMPORTANT]` messages.

**Important:** Flash at least one node via USB to enable OTA. After that, all future updates can be done via the dashboard.

### 5. Build and update additional nodes

**For each additional node:**
```bash
# Build firmware with incremental numbers
./scripts/build_firmware.sh 2
./scripts/build_firmware.sh 3

# Upload via OTA (no USB needed if one node is already online):
# 1. Open dashboard: http://your-server:8091
# 2. Click 📡 Update button next to any online node
# 3. Select builds/soundspy_node2_v0.8.3.bin
# 4. Node downloads, flashes, and reboots (~30 seconds)
```

### 6. OTA updates (after initial flash)
1. Make changes to the firmware code in `node_firmware/`
2. Bump version in `.env`: `FIRMWARE_VERSION=0.8.4`
3. Run build script: `./scripts/build_firmware.sh 1`
4. Open dashboard, click **📡 Update** button
5. Select the new `.bin` file from `builds/` directory
6. Node updates automatically

**Versioning policy (Semantic Versioning):**
See `CHANGELOG.md` for version history and policy.

## Docker Stack Setup

### 1. Prerequisites
- Docker and docker-compose installed
- ESP32 nodes can reach the server (check firewall rules if needed)

### 2. Deploy services
```bash
cd /path/to/soundspy
docker-compose up -d
```

This launches:
- **soundspy_mosquitto** on port 1883 (MQTT broker)
- **soundspy_dashboard** on port 8091 (web interface)
- **soundspy_ntfy** on port 8090 (notifications)
- **soundspy_monitor** (threshold alert service)

### 3. Verify operation
```bash
# Check all containers are running
docker ps

# View dashboard logs
docker logs -f soundspy_dashboard

# View monitor logs
docker logs -f soundspy_monitor

# Subscribe to raw MQTT messages (requires mosquitto-clients)
docker exec soundspy_mosquitto mosquitto_sub -h localhost -t "soundspy/+/data"
```

### 4. Access the dashboard
Open `http://<server-ip>:8091` in your browser. You'll see:
- Live frequency spectrum visualization (bars or wave mode)
- Real-time overall level display with color-coded indicators
- Audio playback controls (mute/unmute per node)
- Remote gain control (affects mic sensitivity)
- Browser volume control (affects playback only)
- Historical charts with selectable time ranges
- Firmware version display
- OTA update interface

## Dashboard Features

**Real-time Monitoring:**
- 6-band frequency spectrum with professional audio meter styling:
  - Green bars: Safe levels (< -20 dBFS)
  - Yellow bars: Caution zone (-10 to -5 dBFS)
  - Red bars: Danger/clipping zone (> -5 dBFS)
- Peak hold markers (fade after 3 seconds)
- Overall level display with animated gradient
- Sequence numbers and latency display

**Audio Streaming:**
- Live audio from each node at 44.1kHz
- Per-node mute/unmute controls
- Browser volume control (0-100%)
- No perceptible latency (<100ms)

**Remote Control:**
- **Mic Gain** (0-100% = 0-20x gain):
  - Affects frequency analysis AND audio
  - Set to 0% to stop all processing
  - Remote control via MQTT
- **Browser Volume** (0-100%):
  - Affects playback only
  - Local to your browser
  - Does not affect frequency readings

**Historical Data:**
- Time range selector: Real-time, 1m, 5m, 10m, 30m, 1h
- Stores up to 1 hour of data (3600 samples @ 50Hz publish rate)
- Chart displays overall level trend

**Visualization Modes:**
- **Bars mode** (default): Professional mixer-style LED meters
- **Wave mode**: Smooth gradient wave with horizontal rainbow gradient

## Calibration

The firmware reports **relative dBFS** (0 dBFS = digital full-scale), NOT calibrated SPL.

### Basic workflow:
1. Set mic gain to comfortable level (default 20% = 4x)
2. Monitor overall level and frequency bands during normal conditions
3. Adjust alert threshold based on what you consider "too loud"
4. Use per-node cooldown to prevent alert spam

### Adjusting threshold:
Edit `docker-compose.yml`:
```yaml
- FREQ_THRESHOLD_DBFS=-20    # Adjust this value (dBFS)
- COOLDOWN_SECONDS=300       # Per-node alert cooldown
```

Then restart:
```bash
docker-compose up -d
```

**Note:** The current threshold system checks overall level. Per-band thresholds are planned for future releases.

## Project Structure

```
soundspy/
├── node_firmware/                  # ESP32/Arduino firmware source code
│   └── node_firmware.ino           # Main firmware (with OTA + I2S watchdog)
├── dashboard/                      # Web dashboard and monitoring services
│   ├── dashboard.py                # Flask + SocketIO web server
│   ├── threshold_monitor.py        # Alert service
│   ├── templates/
│   │   └── dashboard.html          # Web UI
│   ├── Dockerfile.dashboard        # Dashboard container
│   ├── Dockerfile                  # Monitor container
│   └── requirements.txt            # Python dependencies
├── scripts/                        # Build and utility scripts
│   └── build_firmware.sh           # Automated firmware builder
├── builds/                         # Compiled .bin files (auto-generated, git-ignored)
├── mosquitto/                      # MQTT broker configuration
│   ├── config/mosquitto.conf
│   ├── data/                       # MQTT persistence
│   └── log/                        # MQTT logs
├── ntfy/                           # Notification service data
│   ├── cache/
│   └── etc/
├── .env                            # Environment configuration (git-ignored)
├── .env.example                    # Environment template
├── docker-compose.yml              # Docker stack definition
├── CHANGELOG.md                    # Version history
└── README.md                       # This file
```

## Troubleshooting

**ESP32 won't connect to WiFi:**
- Check SSID/password in firmware
- Verify 2.4GHz WiFi is enabled (ESP32 doesn't support 5GHz)
- Check Serial Monitor for connection attempts
- Look for `[IMPORTANT]` tagged messages in serial output

**ESP32 won't connect to MQTT:**
- Verify MQTT_HOST IP is reachable (try ping from another device)
- Check Mosquitto logs: `docker logs soundspy_mosquitto`
- Ensure port 1883 is not blocked by firewall
- Check Serial Monitor for `[IMPORTANT] Subscribed to:` message

**Dashboard not showing firmware version:**
- Wait 10-20 seconds after node connects (version sent in data messages)
- Check dashboard logs: `docker logs soundspy_dashboard | grep version`
- Refresh the dashboard page (Ctrl+Shift+R)

**Audio has noise/static:**
- Place ESP32 on insulating surface (anti-static bag + plastic board)
- Avoid breadboards near USB cables or power supplies
- Check mic is properly seated and connections are solid
- Ground loops can cause electrical noise

**Frequency bars not moving when mic gain = 0:**
- Verify firmware version is 0.7.0 or later (gain applied early in chain)
- Check dashboard shows correct firmware version
- Re-upload firmware if version mismatch

**OTA update fails:**
- Ensure ESP32 can reach the dashboard server via HTTP
- Check Serial Monitor for `[IMPORTANT] OTA` messages
- Verify .bin file is valid (exported from Arduino IDE)
- Try re-flashing via USB if OTA is completely broken

**Spectrum visualization not updating:**
- Check browser console (F12) for JavaScript errors
- Verify WebSocket connection is established
- Refresh dashboard with Ctrl+Shift+R
- Check dashboard logs for WebSocket messages

## Adding More Nodes

The system is designed to scale beyond 3 nodes:

1. **Flash new node:**
   - Change `NODE_ID` to unique name (wall4, wall5, etc.)
   - Flash via USB or use OTA from an existing node's firmware

2. **Dashboard auto-discovery:**
   - Dashboard automatically creates cards for new nodes
   - No configuration changes needed

3. **Grid layout:**
   - Dashboard shows up to 4 nodes per row on wide screens
   - Automatically adjusts for any number of nodes

4. **Resource considerations:**
   - Each node publishes at 50Hz (very lightweight)
   - Audio streaming is on-demand (only when unmuted)
   - MQTT broker can handle dozens of nodes easily

## Future Enhancements

**Completed:**
- ✅ Multi-band frequency analysis (6 bands)
- ✅ Real-time audio streaming
- ✅ Web dashboard with live visualization
- ✅ Remote gain control
- ✅ OTA firmware updates
- ✅ Professional audio meter styling

**Planned:**
- Per-band alert thresholds
- Historical per-band data (currently only overall level)
- Configurable alert thresholds via dashboard UI
- User accounts and authentication
- Mobile-responsive design improvements
- Spectrogram view (waterfall display)
- Audio recording triggers on threshold breach
- Integration with DAW/audio interface
- ML-based adaptive thresholds

## License

MIT
