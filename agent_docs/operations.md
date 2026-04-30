# Operations And Validation

## Validation Commands

Use these before saying a meaningful runtime change is safe:

- `docker compose up -d --build`
- `docker compose ps`
- `docker compose logs --tail=200 exporter`
- `docker compose logs --tail=200 timescaledb`
- `docker compose down -v`

## Deployment Notes

- `docker-compose.yml` defines three services: `exporter`, `timescaledb`, and `grafana`.
- `docker/exporter/Dockerfile.exporter` copies `.env` into the image, so configuration edits may require a rebuild to take effect.
- Grafana provisioning lives under `docker/grafana/provisioning/`.
- The main CI workflow in `.github/workflows/main.yml` is a container-health check, not a unit test suite.
- Migrations under `docker/timescaledb/` only auto-run on a fresh install. Existing deployments must apply each numbered migration manually; in particular, migration `008_retention_and_location_privacy.sql` extends non-location retention from 30 days to 3 months and adds `node_details.location_updated_at`, so apply it before disk-usage assumptions or the location pruner are valid.

## Change Ripple Checklist

If you touch schema, packet structure, or telemetry fields, check all of these:

1. `docker/timescaledb/init.sql`
2. numbered migrations in `docker/timescaledb/`
3. Python inserts and readers in `exporter/db_handler.py` and `exporter/processor/`
4. dashboard queries and panels under `docker/grafana/provisioning/dashboards/`
5. docs and operational scripts if behavior changed

## Utility Scripts

- `scripts/migrate_prometheus_to_timescale.py`: one-time backfill from the older Prometheus-based stack
- `scripts/patch_node_topic_channel_tracking.sh`: operational patch/redeploy helper
- `scripts/prune_location_data.py`: deletes old position history and clears stale latest location fields from `node_details`
- `tools/mqtt_volume_estimator.py`: estimates observation volume from MQTT traffic
