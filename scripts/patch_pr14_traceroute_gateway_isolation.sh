#!/bin/bash
# Patch script for PR #14: fix traceroute hops gateway isolation
# Downloads the 3 changed Python files from main and restarts the exporter.
# No database migrations are required for this patch.
# Usage: cd /path/to/az-meshtastic-metrics-exporter && bash scripts/patch_pr14_traceroute_gateway_isolation.sh

set -e

BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/logans-stuff/az-meshtastic-metrics-exporter/${BRANCH}"

echo "=== Downloading updated files for PR #14 ==="

mkdir -p exporter/processor

echo "[1/3] exporter/db_handler.py"
wget -q -O exporter/db_handler.py "${BASE_URL}/exporter/db_handler.py"

echo "[2/3] exporter/processor/processor_base.py"
wget -q -O exporter/processor/processor_base.py "${BASE_URL}/exporter/processor/processor_base.py"

echo "[3/3] exporter/processor/processors.py"
wget -q -O exporter/processor/processors.py "${BASE_URL}/exporter/processor/processors.py"

echo "Files downloaded successfully."

# Rebuild and restart exporter
echo ""
echo "=== Rebuilding exporter container ==="
docker compose rm -sf exporter || true
docker compose up -d --build --force-recreate exporter

echo ""
echo "=== Done! PR #14 patch applied, exporter restarted. ==="
