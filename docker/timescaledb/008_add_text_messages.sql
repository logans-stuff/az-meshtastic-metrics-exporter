CREATE TABLE IF NOT EXISTS text_message_metrics
(
    time          TIMESTAMPTZ NOT NULL,
    node_id       VARCHAR     NOT NULL,
    to_node_id    VARCHAR     NOT NULL,
    channel       INT,
    packet_id     BIGINT,
    text_payload  TEXT,
    rx_time       BIGINT,
    FOREIGN KEY (node_id) REFERENCES node_details (node_id)
);

SELECT create_hypertable('text_message_metrics', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS idx_text_message_metrics_node_id ON text_message_metrics (node_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_text_message_metrics_to_node ON text_message_metrics (to_node_id, time DESC);

SELECT add_retention_policy('text_message_metrics', INTERVAL '30 days', if_not_exists => TRUE);
