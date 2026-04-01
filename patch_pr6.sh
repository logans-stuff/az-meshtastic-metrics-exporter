#!/bin/bash
# Patch script for PR #6: reporting_gateway per-gateway observation rows
# Downloads changed files from tylerpieper/az-meshtastic-metrics-exporter via wget
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash patch_pr6.sh

set -e

BASE_URL="https://raw.githubusercontent.com/tylerpieper/az-meshtastic-metrics-exporter/main"

echo "=== Patching PR #6: reporting_gateway changes ==="

# Create directories for new files
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
echo "=== Done! All 8 files patched. ==="
echo ""
echo "IMPORTANT: Run the database migration BEFORE restarting the exporter:"
echo "  docker exec -i <timescaledb-container> psql -U postgres -d <db> < docker/timescaledb/002_reporting_gateway_migration.sql"
