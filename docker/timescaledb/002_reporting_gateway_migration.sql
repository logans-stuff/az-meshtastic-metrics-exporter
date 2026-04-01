-- Migration script to alter mesh_packet_metrics to support reporting_gateway

ALTER TABLE mesh_packet_metrics 
    ADD COLUMN IF NOT EXISTS reporting_gateway VARCHAR DEFAULT NULL;

-- Drop the old unique constraint (which used relay_node)
ALTER TABLE mesh_packet_metrics 
    DROP CONSTRAINT IF EXISTS mesh_packet_metrics_unique_packet;
ALTER TABLE mesh_packet_metrics 
    DROP CONSTRAINT IF EXISTS mesh_packet_metrics_time_packet_id_source_id_relay_no_key;

-- Add the new unique constraint using reporting_gateway instead of relay_node
ALTER TABLE mesh_packet_metrics 
    ADD CONSTRAINT mesh_packet_metrics_time_packet_id_source_id_reporting__key 
    UNIQUE (time, packet_id, source_id, reporting_gateway);

-- Add index on reporting_gateway
CREATE INDEX IF NOT EXISTS idx_mesh_packet_metrics_gateway ON mesh_packet_metrics (reporting_gateway, time DESC);
