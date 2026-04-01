ALTER TABLE node_details
    ADD COLUMN IF NOT EXISTS last_heard_topic VARCHAR,
    ADD COLUMN IF NOT EXISTS last_heard_channel VARCHAR,
    ADD COLUMN IF NOT EXISTS mqtt_direct_topic VARCHAR;
