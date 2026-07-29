#!/bin/bash
# Quick deployment test script for soundspy

set -e

echo "=== soundspy deployment test ==="
echo ""

echo "[1/5] Checking project structure..."
for dir in monitor_node mosquitto/config ntfy; do
  if [ ! -d "$dir" ]; then
    echo "❌ Missing directory: $dir"
    exit 1
  fi
done
echo "✓ Directory structure OK"
echo ""

echo "[2/5] Checking required files..."
for file in monitor_node/node.ino docker-compose.yml Dockerfile threshold_monitor.py requirements.txt mosquitto/config/mosquitto.conf; do
  if [ ! -f "$file" ]; then
    echo "❌ Missing file: $file"
    exit 1
  fi
done
echo "✓ All required files present"
echo ""

echo "[3/5] Building/pulling Docker images..."
docker-compose build --quiet
docker-compose pull --quiet
echo "✓ Docker images ready"
echo ""

echo "[4/5] Starting services..."
docker-compose up -d
sleep 3
echo "✓ Services started"
echo ""

echo "[5/5] Checking service health..."
for service in soundspy-mosquitto soundspy-ntfy soundspy-monitor; do
  if docker ps | grep -q "$service"; then
    status=$(docker ps --filter "name=$service" --format "{{.Status}}")
    echo "✓ $service: $status"
  else
    echo "❌ $service: not running"
    docker logs "$service" | tail -10
    exit 1
  fi
done
echo ""

echo "=== Deployment test complete ==="
echo ""
echo "Next steps:"
echo "1. Check logs: docker logs -f soundspy_monitor"
echo "2. Subscribe to MQTT: mosquitto_sub -h localhost -t 'bassmonitor/+/data' -v"
echo "3. Open ntfy web UI: http://localhost:8090/bassmonitor"
echo "4. Flash ESP32 nodes with monitor_node/node.ino (edit NODE_ID per board)"
echo ""
