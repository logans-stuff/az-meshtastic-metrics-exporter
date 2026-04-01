#!/bin/bash
# Patch script for PR #8: reporting_gateway + node topic/channel tracking
# Downloads all changed files and applies DB migrations via wget pipe
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash patch_pr6.sh

set -e

BRANCH="claude/review-pull-request-KQB1O"
BASE_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/${BRANCH}"
CONTAINER="az-meshtastic-metrics-exporter-timescaledb-1"
DB_USER="postgres"
DB_NAME="meshtastic"

# Step 1: Apply database migrations BEFORE updating code
echo "=== Step 1: Applying database migrations ==="

echo "[migration 1/2] 002_reporting_gateway_migration.sql"
wget -qO- "${BASE_URL}/docker/timescaledb/002_reporting_gateway_migration.sql" | docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

echo "[migration 2/2] 003_node_topic_channel_tracking.sql"
wget -qO- "${BASE_URL}/docker/timescaledb/003_node_topic_channel_tracking.sql" | docker exec -i "${CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

echo "Migrations applied successfully."

# Step 2: Download all updated files
echo ""
echo "=== Step 2: Downloading updated files ==="

mkdir -p tools
mkdir -p scripts
mkdir -p docker/timescaledb

echo "[ 1/11] .gitignore"
wget -q -O .gitignore "${BASE_URL}/.gitignore"

echo "[ 2/11] docker/timescaledb/002_reporting_gateway_migration.sql"
wget -q -O docker/timescaledb/002_reporting_gateway_migration.sql "${BASE_URL}/docker/timescaledb/002_reporting_gateway_migration.sql"

echo "[ 3/11] docker/timescaledb/003_node_topic_channel_tracking.sql"
wget -q -O docker/timescaledb/003_node_topic_channel_tracking.sql "${BASE_URL}/docker/timescaledb/003_node_topic_channel_tracking.sql"

echo "[ 4/11] docker/timescaledb/init.sql"
wget -q -O docker/timescaledb/init.sql "${BASE_URL}/docker/timescaledb/init.sql"

echo "[ 5/11] exporter/db_handler.py"
wget -q -O exporter/db_handler.py "${BASE_URL}/exporter/db_handler.py"

echo "[ 6/11] exporter/processor/processor_base.py"
wget -q -O exporter/processor/processor_base.py "${BASE_URL}/exporter/processor/processor_base.py"

echo "[ 7/11] exporter/processor/processors.py"
wget -q -O exporter/processor/processors.py "${BASE_URL}/exporter/processor/processors.py"

echo "[ 8/11] main.py"
wget -q -O main.py "${BASE_URL}/main.py"

echo "[ 9/11] README.md"
wget -q -O README.md "${BASE_URL}/README.md"

echo "[10/11] tools/mqtt_volume_estimator.py"
wget -q -O tools/mqtt_volume_estimator.py "${BASE_URL}/tools/mqtt_volume_estimator.py"

echo "[11/11] scripts/patch_node_topic_channel_tracking.sh"
wget -q -O scripts/patch_node_topic_channel_tracking.sh "${BASE_URL}/scripts/patch_node_topic_channel_tracking.sh"
chmod +x scripts/patch_node_topic_channel_tracking.sh

# Step 3: Rebuild and restart exporter
echo ""
echo "=== Step 3: Rebuilding exporter container ==="
docker compose rm -sf exporter || true
docker compose up -d --build --force-recreate exporter

echo ""
echo "=== Done! Migrations applied, files patched, exporter restarted. ==="
