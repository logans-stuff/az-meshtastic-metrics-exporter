#!/bin/bash
# Patch script: downloads updated files for the packet timestamps + position dedup feature
# Usage: ./scripts/patch_packet_timestamps.sh
# Run from the repository root directory.

set -euo pipefail

REPO="logans-stuff/az-meshtastic-metrics-exporter"
BRANCH="claude/review-datetime-handling-rK0sn"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

FILES=(
    "docker/timescaledb/004_add_packet_timestamps.sql"
    "docker/timescaledb/init.sql"
    "exporter/processor/processors.py"
)

echo "Patching from ${REPO}@${BRANCH}"
echo "---"

for file in "${FILES[@]}"; do
    dir=$(dirname "$file")
    mkdir -p "$dir"
    echo "Downloading ${file}..."
    curl -fsSL "${BASE_URL}/${file}" -o "$file"
done

echo "---"
echo "Done. Files updated:"
printf "  %s\n" "${FILES[@]}"
echo ""
echo "Next steps:"
echo "  1. Run the migration on your database:"
echo "     psql -U \$DB_USER -d \$DB_NAME -f docker/timescaledb/004_add_packet_timestamps.sql"
echo "  2. Restart the exporter to pick up the processor changes"
echo "  3. Verify new columns with: \\d position_metrics  (should show packet_id, rx_time, message_timestamp)"
