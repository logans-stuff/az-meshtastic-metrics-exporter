-- Migration: extend non-location TimescaleDB retention, shorten position
-- history, and add an explicit timestamp for the latest-location fields on
-- node_details so location pruning is unambiguous.
--
-- General telemetry and packet metadata are useful for longer-term network
-- trend analysis, so retain them for 3 months. Historical positions are more
-- sensitive, so keep only 30 days in the automatic Timescale retention policy.
--
-- node_details.location_updated_at records when the lat/lon/alt/precision
-- columns on the row were last written, distinct from updated_at (which is
-- bumped by any node-info change). The location pruner uses it to decide
-- whether the cached "latest location" is stale even after position_metrics
-- chunks have been dropped by retention.

DO $$
DECLARE
    metric_table REGCLASS;
BEGIN
    FOREACH metric_table IN ARRAY ARRAY[
        'device_metrics'::REGCLASS,
        'environment_metrics'::REGCLASS,
        'air_quality_metrics'::REGCLASS,
        'power_metrics'::REGCLASS,
        'pax_counter_metrics'::REGCLASS,
        'mesh_packet_metrics'::REGCLASS
    ]
    LOOP
        PERFORM remove_retention_policy(metric_table, if_exists => TRUE);
        PERFORM add_retention_policy(metric_table, INTERVAL '3 months');
    END LOOP;

    PERFORM remove_retention_policy('position_metrics'::REGCLASS, if_exists => TRUE);
    PERFORM add_retention_policy('position_metrics'::REGCLASS, INTERVAL '30 days');
END $$;

ALTER TABLE node_details
    ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMP;

-- Backfill only when position history proves when the cached location was
-- observed. Rows without retained position history stay NULL so operators can
-- clear them intentionally with the pruner's --force-legacy flag.
UPDATE node_details nd
SET location_updated_at = lp.latest
FROM (
    SELECT node_id, MAX(time) AS latest
    FROM position_metrics
    GROUP BY node_id
) lp
WHERE lp.node_id = nd.node_id
  AND nd.location_updated_at IS NULL
  AND (
      nd.latitude IS NOT NULL
      OR nd.longitude IS NOT NULL
      OR nd.altitude IS NOT NULL
      OR nd.precision IS NOT NULL
  );
