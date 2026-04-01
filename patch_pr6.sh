#!/bin/bash
# Patch script for PR #6: reporting_gateway per-gateway observation rows
# Downloads changed files from logans-stuff/az-meshtastic-metrics-exporter via wget
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash patch_pr6.sh

set -e

BASE_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/main"
CONTAINER="az-meshtastic-metrics-exporter-timescaledb-1"
DB_USER="postgres"
DB_NAME="meshtastic"

# Step 1: Apply database migration BEFORE updating code
echo "=== Step 1: Applying database migration ==="
wget -qO- "${BASE_URL}/docker/timescaledb/002_reporting_gateway_migration.sql" | docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
echo "Migration applied successfully."

# Step 2: Download updated files
echo ""
echo "=== Step 2: Downloading updated files ==="

mkdir -p tools
mkdir -p docker/timescaledb

echo "[1/8] .gitignore"
wget -q -O .gitignore "${BASE_URL}/.gitignore"

echo "[2/8] docker/timescaledb/002_reporting_gateway_migration.sql (new)"
wget -q -O docker/timescaledb/002_reporting_gateway_migration.sql "${BASE_URL}/docker/timescaledb/002_reporting_gateway_migration.sql"

echo "[3/8] docker/timescaledb/init.sql"
wget -q -O docker/timescaledb/init.sql "${BASE_URL}/docker/timescaledb/init.sql"

echo "[4/8] exporter/db_handler.py"
wget -q -O exporter/db_handler.py "${BASE_URL}/exporter/db_handler.py"

echo "[5/8] exporter/processor/processor_base.py"
wget -q -O exporter/processor/processor_base.py "${BASE_URL}/exporter/processor/processor_base.py"

echo "[6/8] exporter/processor/processors.py"
wget -q -O exporter/processor/processors.py "${BASE_URL}/exporter/processor/processors.py"

echo "[7/8] main.py"
wget -q -O main.py "${BASE_URL}/main.py"

echo "[8/8] tools/mqtt_volume_estimator.py (new)"
wget -q -O tools/mqtt_volume_estimator.py "${BASE_URL}/tools/mqtt_volume_estimator.py"

echo ""
echo "=== Done! Migration applied and all 8 files patched. ==="
echo "Restart the exporter to pick up changes:"
echo "  docker compose restart exporter"
