#!/bin/bash
# Patch script for PR #18 (ok_to_mqtt extraction) + PR #19 (bitfield guard fix)
# Pulls files from the claude/review-meshtastic-pr-5tLx8 branch, which already
# contains PR #18's feature merged into main plus the PR #19 follow-up fix.
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash patch_pr18_19.sh

set -e

BRANCH="claude/review-meshtastic-pr-5tLx8"
BASE_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/${BRANCH}"
CONTAINER="az-meshtastic-metrics-exporter-timescaledb-1"
DB_USER="postgres"
DB_NAME="meshtastic"

# Step 1: Apply database migration BEFORE updating code
echo "=== Step 1: Applying database migration ==="

echo "[migration 1/1] 007_add_ok_to_mqtt.sql"
wget -qO- "${BASE_URL}/docker/timescaledb/007_add_ok_to_mqtt.sql" | docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

echo "Migration applied successfully."

# Step 2: Download all updated files
echo ""
echo "=== Step 2: Downloading updated files ==="

mkdir -p docker/timescaledb
mkdir -p exporter/processor

echo "[1/3] docker/timescaledb/007_add_ok_to_mqtt.sql"
wget -q -O docker/timescaledb/007_add_ok_to_mqtt.sql "${BASE_URL}/docker/timescaledb/007_add_ok_to_mqtt.sql"

echo "[2/3] docker/timescaledb/init.sql"
wget -q -O docker/timescaledb/init.sql "${BASE_URL}/docker/timescaledb/init.sql"

echo "[3/3] exporter/processor/processor_base.py"
wget -q -O exporter/processor/processor_base.py "${BASE_URL}/exporter/processor/processor_base.py"

# Step 3: Rebuild and restart exporter
echo ""
echo "=== Step 3: Rebuilding exporter container ==="
docker compose rm -sf exporter || true
docker compose up -d --build --force-recreate exporter

echo ""
echo "=== Done! Migration applied, files patched, exporter restarted. ==="
