-- Migration: Traceroute dead-end fix + Position history
--
-- For existing TimescaleDB deployments, run this script manually against your database:
--
--   psql -h <host> -U <user> -d <database> -f docker/timescaledb/001_traceroute_and_positions_migration.sql
--
-- Or if using Docker:
--
--   docker exec -i <timescaledb_container> psql -U <user> -d <database> < docker/timescaledb/001_traceroute_and_positions_migration.sql
--
-- This is safe to run on a live database — it does not drop data or require downtime.
-- New deployments using init.sql do not need this script.

-- Issue 1: Fix dropped traceroutes from dead ends by expanding the unique constraint boundary
-- to consider the specific node that relayed it. TimescaleDB hypertables require partitioning
-- column 'time' as part of the unique key natively.
ALTER TABLE mesh_packet_metrics DROP CONSTRAINT IF EXISTS mesh_packet_metrics_packet_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mesh_packet_metrics_unique_packet
ON mesh_packet_metrics (time, packet_id, source_id, COALESCE(relay_node, 0));

-- Issue 2: Retain position packet history to enable GPS drift calculations for stationary nodes.
CREATE TABLE position_metrics (
    time TIMESTAMPTZ NOT NULL,
    node_id VARCHAR NOT NULL,
    latitude INT,
    longitude INT,
    altitude INT,
    precision INT,
    FOREIGN KEY (node_id) REFERENCES node_details (node_id)
);

-- Convert the standard table into a hypertable for chunking
SELECT create_hypertable('position_metrics', 'time');

-- Apply indexing for optimal dashboard loads
CREATE INDEX idx_position_metrics_node_id ON position_metrics (node_id, time DESC);

-- Apply standard 30-day retention policies using timescale plugin
SELECT add_retention_policy('position_metrics', INTERVAL '30 days');
