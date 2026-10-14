# CLAUDE.md

These dashboard JSON files are part of the shipped product, not throwaway assets.

## Review Focus

- Assume dashboard queries depend on current SQL table names, column names, and view names.
- If backend schema changes, verify whether these dashboards now reference stale fields.
- Prefer keeping dashboard semantics aligned with the current TimescaleDB schema instead of patching around drift in the UI layer.

## Cross-Check With

- `docker/timescaledb/init.sql`
- migration files in `docker/timescaledb/`
- `docker/grafana/provisioning/datasources/datasources.yml`
