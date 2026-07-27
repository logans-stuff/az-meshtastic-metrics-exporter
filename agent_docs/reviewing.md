# Reviewing This Repository

Use this when asked to review the project, validate broad changes, or assess repository health.

## What A Full Review Means

A full review in this repository includes all of the following:

1. Runtime packet handling
   - `main.py`
   - `constants.py`
   - `exporter/client_details.py`
   - `exporter/db_handler.py`
   - `exporter/processor/processor_base.py`
   - `exporter/processor/processors.py`
2. Database schema and migrations
   - `docker/timescaledb/init.sql`
   - the numbered migration files in `docker/timescaledb/`, currently `001` through `009`
3. Deployment and operations
   - `docker-compose.yml`
   - `docker/exporter/Dockerfile.exporter`
   - `docker/grafana/Dockerfile.grafana`
   - `.env`
4. Dashboards and provisioning
   - `docker/grafana/provisioning/datasources/datasources.yml`
   - dashboard JSON files under `docker/grafana/provisioning/dashboards/`
5. CI, scripts, and docs
   - `.github/workflows/main.yml`
   - `.github/workflows/auto-tagging.yml`
   - `scripts/`
   - `tools/`
   - `README.md`
   - `CONTRIBUTING.md`

If you skipped any of those, say the review was partial.

## Highest-Value Review Questions

- Can this change drop packets, mis-deduplicate packets, or create duplicate rows?
- Does Python still match the live schema and migration path?
- Did any table or column rename silently break Grafana dashboards?
- Did a deployment or config change alter runtime behavior in Docker?
- Did docs or scripts become stale relative to the code?
- Did the change preserve compatibility with both protobuf import paths?

## Repo-Specific Risks

- `exporter/db_handler.py` builds INSERT column lists dynamically, so metric keys must match real columns.
- Schema changes usually require coordinated edits in SQL, Python, and often Grafana JSON.
- Several processors are placeholders with `pass`; do not assume every Meshtastic port is implemented.
- The repo still contains some historical Prometheus-era wording in docs; prefer current code and SQL if docs conflict.
