# CLAUDE.md

This directory defines the live database contract for the project.

## Important Rule

Treat `init.sql` and the numbered migration files as a coordinated set. Do not update one and forget the others when behavior or schema meaning changes.

## Files

- `init.sql`: source of truth for fresh installs
- `001_traceroute_and_positions_migration.sql`: older traceroute/position history migration
- `002_reporting_gateway_migration.sql`: reporting gateway uniqueness migration
- `003_node_topic_channel_tracking.sql`: node topic/channel tracking migration
- `004_add_packet_timestamps.sql`: adds rx_time and message_timestamp to metric hypertables

## Review Focus

- Check that Python inserts and reads still match table names, column names, unique constraints, and views.
- Be careful with TimescaleDB hypertable constraints, retention policies, triggers, and views.
- Verify whether a schema change also affects dashboard queries and operational scripts.

## Cross-Check After SQL Changes

- `exporter/db_handler.py`
- `exporter/processor/processor_base.py`
- `exporter/processor/processors.py`
- `docker/grafana/provisioning/dashboards/`
- `scripts/`
