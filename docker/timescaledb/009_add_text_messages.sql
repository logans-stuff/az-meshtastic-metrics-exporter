-- Migration: capture TEXT_MESSAGE_APP and TEXT_MESSAGE_COMPRESSED_APP payloads.
--
-- Message bodies are the most sensitive thing this exporter can persist, so the
-- retention policy matches position_metrics at 30 days rather than the 3 months
-- used for general telemetry in migration 008.
--
-- reporting_gateway records which MQTT uplink reported the message. There is
-- deliberately no unique constraint here: the same message relayed by several
-- gateways is stored once per uplink, consistent with how mesh_packet_metrics
-- observations are counted.

CREATE TABLE IF NOT EXISTS text_message_metrics
(
    time              TIMESTAMPTZ NOT NULL,
    node_id           VARCHAR     NOT NULL,
    to_node_id        VARCHAR     NOT NULL,
    channel           INT,
    packet_id         BIGINT,
    text_payload      TEXT,
    rx_time           BIGINT,
    reporting_gateway VARCHAR DEFAULT NULL,
    FOREIGN KEY (node_id) REFERENCES node_details (node_id)
);

-- Deployments that already applied this migration under its original 008 name
-- predate the reporting_gateway column.
ALTER TABLE text_message_metrics
    ADD COLUMN IF NOT EXISTS reporting_gateway VARCHAR DEFAULT NULL;

SELECT create_hypertable('text_message_metrics', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS idx_text_message_metrics_node_id ON text_message_metrics (node_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_text_message_metrics_to_node ON text_message_metrics (to_node_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_text_message_metrics_gateway ON text_message_metrics (reporting_gateway, time DESC);

SELECT add_retention_policy('text_message_metrics', INTERVAL '30 days', if_not_exists => TRUE);
