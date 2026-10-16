# Contributing

## Running it locally

```bash
cp .env.example .env            # broker address and credentials
docker compose up -d            # pulls ghcr.io/rojosinalma/soundspy:latest
```

To work on the dashboard source, add a git-ignored `compose.override.yaml` with a `build:` block and a `./dashboard:/app` mount (see `docs/development.md`) and run `docker compose up -d --build`. Firmware builds need arduino-cli: `./scripts/init_arduino.sh`, then `./scripts/build_firmware.sh` (needs the Esp32Base library via `ESP32_BASE_DIR`) or `./scripts/build_firmware.sh legacy`.

## Tests

There is no automated test suite yet. Before opening a PR:

- `python -m py_compile dashboard/*.py`, `GET /health` on the running container, and a run against a broker with at least one node (or `mosquitto_pub` of a `status` + `data` message on `esp32/<id>/…`).
- `./scripts/build_firmware.sh legacy` must compile; CI (`build-firmware`) runs the same build on every push and PR touching `node_firmware/`, `scripts/` or `partitions.csv`.
- `bash -n scripts/*.sh` for shell changes.

## Code style and layout

- Python: standard library first, small modules with one job (`app.py` routes and MQTT glue, `node_state.py` live state, `db.py` persistence, `audio_relay.py`, `notifications.py`). No business logic in route handlers beyond validation and a call.
- Firmware: `firmware/soundspy.ino` stays a thin reporter; audio work goes in `audio.cpp`. Settings get validated in `Settings::apply` and are reported in the status.
- Bounded memory: every in-memory collection has a cap (history deques, log deque, relay count).
- Shell scripts: `set -e`, resolve the project root from the script location, no absolute paths.
- Keep configurable values configurable (environment, database, node settings); no new hard-coded hosts or ports.

## Commits and PRs

- Plain, descriptive commit messages in the imperative (`Fix relay reconnect after node sleep`), one logical change per commit.
- Every commit is GPG- or SSH-signed (`git config commit.gpgsign true`); unsigned commits are not merged.
- Firmware version bumps go through `./scripts/bump_version.sh` and a `CHANGELOG.md` entry in the same commit.
- PRs describe what changed and how it was verified (which board, which broker, what you saw in the dashboard).

## Documentation

| File | Content |
|---|---|
| `README.md` | What it is, requirements, the shortest setup |
| `docs/SDD.md` | Design: architecture, data model, flows, decisions, scope, operations |
| `docs/hardware.md` | Wiring, carrier PCB, enclosure |
| `docs/firmware.md` | Toolchain, building, flashing, settings, MQTT topics, OTA, legacy firmware |
| `docs/dashboard.md` | Configuration, UI, live audio, alerts, HTTP API |
| `docs/adding-nodes.md` | Bringing up another node |
| `docs/troubleshooting.md` | Symptoms and what to check |
| `docs/development.md` | Repository layout, dev loop, releasing |
| `case/README.md`, `pcb/inmp441/DESIGN.md` | Enclosure and PCB specifics |
| `CHANGELOG.md` | Keep a Changelog, one section per version |
| `SECURITY.md`, `CODE_OF_CONDUCT.md` | Vulnerability reporting, community rules |

A change in behaviour comes with the matching doc change in the same PR.

## Releasing

1. `./scripts/bump_version.sh <x.y.z>` (updates `VERSION`, `APP_VERSION`, `DASHBOARD_VERSION`).
2. Add `## [x.y.z] - <date>` to `CHANGELOG.md`.
3. Commit and push to `main`. The `release` workflow tags `vx.y.z`, creates the GitHub release from the changelog section, and dispatches `build-firmware` (attaches the legacy firmware binaries) and `publish-image` (`ghcr.io/rojosinalma/soundspy:x.y.z`, `:x.y`, `:latest`) for the tag.
4. PCB releases are separate: bump `pcb/inmp441/VERSION` and the `publish-pcb` workflow zips the KiCad project into a `pcb-inmp441-v<version>` release.
