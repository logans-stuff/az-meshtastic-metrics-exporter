#!/bin/bash
# Patch script to wget files changed in the last 5 days from GitHub
# Run this from the root of your az-meshtastic-metrics-exporter directory

set -e

REPO="logans-stuff/az-meshtastic-metrics-exporter"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

FILES=(
    "docker/timescaledb/001_traceroute_and_positions_migration.sql"
    "docker/timescaledb/init.sql"
    "exporter/db_handler.py"
    "exporter/processor/processors.py"
)

echo "Patching files from ${REPO}@${BRANCH}..."
echo ""

for file in "${FILES[@]}"; do
    dir=$(dirname "$file")
    mkdir -p "$dir"
    echo "Downloading: $file"
    if wget -q -O "$file" "${BASE_URL}/${file}"; then
        echo "  OK"
    else
        echo "  FAILED - $file"
    fi
done

echo ""
echo "Done. Patched ${#FILES[@]} files."
