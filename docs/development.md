# Development

## Layout

```
firmware/                 Current node firmware (Esp32Base): soundspy.ino, audio.{h,cpp}
node_firmware/            Legacy standalone firmware + recovery_firmware/ (factory slot image)
partitions.csv            4 MB partition table used by the legacy firmware (factory + two app slots)
dashboard/                Flask/Socket.IO service: app.py, db.py, node_state.py, audio_relay.py,
                          notifications.py, helpers.py, templates/, Dockerfile.dashboard
pcb/inmp441/              KiCad carrier board, DESIGN.md, VERSION (drives publish-pcb)
case/                     OpenSCAD enclosures, STLs and previews (see case/README.md)
scripts/                  init_arduino.sh, build_firmware.sh, flash_initial.sh, flash_wsl.sh,
                          deploy_ota.sh (legacy), serial_monitor.sh, render_case.sh, bump_version.sh
docs/                     This documentation; docs/SDD.md is the design document
```

## Dashboard

Run it from a checkout with a local override that mounts the source and builds the image:

```yaml
# compose.override.yaml (git-ignored)
services:
  soundspy:
    build: {context: ./dashboard, dockerfile: Dockerfile.dashboard}
    volumes:
      - ./dashboard:/app
```

```bash
docker compose up -d --build
docker logs -f soundspy
```

Templates reload automatically (`TEMPLATES_AUTO_RELOAD`); Python changes need `docker compose restart soundspy`. Without Docker: `cd dashboard && pip install -r requirements.txt && python app.py` with `MQTT_HOST` and `DB_PATH` in the environment.

## Firmware

```bash
./scripts/init_arduino.sh
ESP32_BASE_DIR=/path/to/Esp32Base ./scripts/build_firmware.sh   # firmware/
./scripts/build_firmware.sh legacy                                # node_firmware/
./scripts/serial_monitor.sh                                       # all /dev/ttyUSB*
```

Flashing, the setup portal and OTA are in [firmware.md](firmware.md). Keep `APP_VERSION` (firmware), `DASHBOARD_VERSION` (dashboard) and `VERSION` in step with `./scripts/bump_version.sh`.

## Enclosure and PCB

`./scripts/render_case.sh [-D param=value]` re-renders the STLs and preview PNGs with the OpenSCAD CLI (or a container through `OPENSCAD=…`) after a collision check against the board model. Bump `pcb/inmp441/VERSION` to publish a new PCB release.

## Releasing

1. `./scripts/bump_version.sh <x.y.z>` and add a `## [x.y.z]` section to `CHANGELOG.md`.
2. Commit and push to `main`. The `release` workflow sees the changed `VERSION`, creates tag `vx.y.z` and a GitHub release with the changelog section, then dispatches `build-firmware` on the tag, which attaches the legacy firmware binaries. `publish-image` pushes `ghcr.io/rojosinalma/soundspy:x.y.z`, `:x.y` and `:latest`.
