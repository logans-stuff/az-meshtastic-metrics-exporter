#!/bin/bash
# Patch script for PR #18 (ok_to_mqtt extraction, merged to main) +
# PR #19 (bitfield guard fix, unmerged on claude/review-meshtastic-pr-5tLx8).
# Pulls PR #18 files straight from main and only the fix from the PR #19 branch.
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash patch_pr18_19.sh

set -e

MAIN_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/main"
FIX_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/claude/review-meshtastic-pr-5tLx8"

DB_CONTAINER="az-meshtastic-metrics-exporter-timescaledb-1"
EXPORTER_CONTAINER="az-meshtastic-metrics-exporter-exporter-1"
DB_USER="postgres"
DB_NAME="meshtastic"

# Step 1: Apply database migration BEFORE updating code (from main, since #18 is merged)
echo "=== Step 1: Applying database migration ==="

echo "[migration 1/1] 007_add_ok_to_mqtt.sql"
wget -qO- "${MAIN_URL}/docker/timescaledb/007_add_ok_to_mqtt.sql" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

echo "Migration applied successfully."

# Step 2: Download updated files
echo ""
echo "=== Step 2: Downloading updated files ==="

mkdir -p docker/timescaledb
mkdir -p exporter/processor

# PR #18 files live on main (already merged)
echo "[1/3] docker/timescaledb/007_add_ok_to_mqtt.sql (main)"
wget -q -O docker/timescaledb/007_add_ok_to_mqtt.sql "${MAIN_URL}/docker/timescaledb/007_add_ok_to_mqtt.sql"

echo "[2/3] docker/timescaledb/init.sql (main)"
wget -q -O docker/timescaledb/init.sql "${MAIN_URL}/docker/timescaledb/init.sql"

# PR #19's fix lives only on the PR branch
echo "[3/3] exporter/processor/processor_base.py (PR #19 branch)"
wget -q -O exporter/processor/processor_base.py "${FIX_URL}/exporter/processor/processor_base.py"

# Step 3: Rebuild and restart exporter
echo ""
echo "=== Step 3: Rebuilding exporter container (${EXPORTER_CONTAINER}) ==="
docker compose rm -sf exporter || true
docker compose up -d --build --force-recreate exporter

echo ""
echo "=== Done! Migration applied, files patched, exporter restarted. ==="
