-- Migration: Add rx_time and message_timestamp to metric hypertables
-- Keeps datetime.now() as 'time' (server ingestion time) and adds:
--   rx_time: gateway RF receive timestamp (epoch seconds from MeshPacket.rx_time)
--   message_timestamp: originating node's timestamp (epoch seconds from protobuf payload)
-- Together these enable message-life analysis, mesh transit delay, and MQTT latency calculations.

-- Position metrics: also add packet_id for deduplication across gateways
ALTER TABLE position_metrics ADD COLUMN IF NOT EXISTS packet_id BIGINT;
ALTER TABLE position_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE position_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;
CREATE INDEX IF NOT EXISTS idx_position_metrics_packet_node ON position_metrics (packet_id, node_id);

-- Device metrics
ALTER TABLE device_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE device_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;

-- Environment metrics
ALTER TABLE environment_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE environment_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;

-- Air quality metrics
ALTER TABLE air_quality_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE air_quality_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;

-- Power metrics
ALTER TABLE power_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE power_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;

-- PAX counter metrics
ALTER TABLE pax_counter_metrics ADD COLUMN IF NOT EXISTS rx_time BIGINT;
ALTER TABLE pax_counter_metrics ADD COLUMN IF NOT EXISTS message_timestamp BIGINT;
