#!/usr/bin/env bash
set -euo pipefail

# Re-roll exporter by copying updated files into a compose project, removing the old
# exporter container/images, rebuilding, and recreating the container. Also applies
# the mesh_packet_metrics request_id/reply_id migration so the ingest path keeps
# matching the live schema.
# Usage:
#   ./scripts/patch_request_reply_ids.sh [compose_project_dir]
# Examples:
#   ./scripts/patch_request_reply_ids.sh
#   ./scripts/patch_request_reply_ids.sh /opt/meshtastic-metrics-exporter

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
install -m 0644 "${PATCH_SOURCE_ROOT}/exporter/processor/processor_base.py" \
  "${TARGET_REPO_ROOT}/exporter/processor/processor_base.py"
install -m 0644 "${PATCH_SOURCE_ROOT}/docker/timescaledb/init.sql" \
  "${TARGET_REPO_ROOT}/docker/timescaledb/init.sql"
install -m 0644 "${PATCH_SOURCE_ROOT}/docker/timescaledb/006_add_request_reply_ids.sql" \
  "${TARGET_REPO_ROOT}/docker/timescaledb/006_add_request_reply_ids.sql"

echo "Applying DB migration before restarting exporter"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" exec -T timescaledb \
  psql -U "${DB_USER}" -d "${DB_NAME}" \
  -f /dev/stdin < "${TARGET_REPO_ROOT}/docker/timescaledb/006_add_request_reply_ids.sql"

echo "Removing old exporter container"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" rm -sf exporter || true

echo "Rebuilding and recreating exporter container"
docker compose -f "${TARGET_REPO_ROOT}/${COMPOSE_FILE}" up -d --build --force-recreate exporter

echo "Re-roll + DB patch complete"
