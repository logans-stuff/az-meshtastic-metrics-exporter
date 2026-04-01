#!/usr/bin/env bash
set -euo pipefail

# Re-roll exporter by copying updated files into a compose project, removing the old
# exporter container/images, rebuilding, and recreating the container.
# Usage:
#   ./scripts/patch_node_topic_channel_tracking.sh [compose_project_dir]
# Examples:
#   ./scripts/patch_node_topic_channel_tracking.sh
#   ./scripts/patch_node_topic_channel_tracking.sh /opt/meshtastic-metrics-exporter

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SOURCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_REPO_ROOT="${1:-${PATCH_SOURCE_ROOT}}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DB_NAME="${POSTGRES_DB:-meshtastic}"
DB_USER="${POSTGRES_USER:-postgres}"

if [[ ! -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" ]]; then
  echo "Compose file not found at ${TARGET_REPO_ROOT}/${COMPOSE_FILE}"
  exit 1
fi

echo "Copying updated exporter files into ${TARGET_REPO_ROOT}"
install -m 0644 "${PATCH_SOURCE_ROOT}/main.py" "${TARGET_REPO_ROOT}/main.py"
install -m 0644 "${PATCH_SOURCE_ROOT}/exporter/processor/processor_base.py" \
  "${TARGET_REPO_ROOT}/exporter/processor/processor_base.py"
install -m 0644 "${PATCH_SOURCE_ROOT}/docker/timescaledb/003_node_topic_channel_tracking.sql" \
  "${TARGET_REPO_ROOT}/docker/timescaledb/003_node_topic_channel_tracking.sql"

echo "Removing old exporter container"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" rm -sf exporter || true

echo "Purging dangling/old images"
docker image prune -af

echo "Rebuilding and recreating exporter container"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" up -d --build --force-recreate exporter

echo "Applying DB migration through compose service: timescaledb"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" exec -T timescaledb \
  psql -U "${DB_USER}" -d "${DB_NAME}" \
  -f /dev/stdin < "${TARGET_REPO_ROOT}/docker/timescaledb/003_node_topic_channel_tracking.sql"

echo "Re-roll + DB patch complete"
