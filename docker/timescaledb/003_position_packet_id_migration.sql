-- Add packet_id to position_metrics
ALTER TABLE position_metrics ADD COLUMN IF NOT EXISTS packet_id BIGINT;

-- Create an index to speed up deduplication lookups based on packet_id and node_id
CREATE INDEX IF NOT EXISTS idx_position_metrics_packet_node ON position_metrics (packet_id, node_id);
