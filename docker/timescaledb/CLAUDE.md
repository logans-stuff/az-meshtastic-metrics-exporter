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
- `005_neighbor_info_history.sql`: neighbor info history migration
- `006_add_request_reply_ids.sql`: adds request_id and reply_id to mesh_packet_metrics
- `007_add_ok_to_mqtt.sql`: adds the ok_to_mqtt flag
- `008_retention_and_location_privacy.sql`: extends telemetry retention to 3 months, keeps positions at 30 days, adds node_details.location_updated_at
- `009_add_text_messages.sql`: adds the text_message_metrics hypertable for captured message bodies

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
