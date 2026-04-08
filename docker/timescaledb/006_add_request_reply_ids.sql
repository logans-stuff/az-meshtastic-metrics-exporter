-- Migration: add request_id and reply_id to mesh_packet_metrics.
-- These fields live on the Meshtastic Data protobuf (alongside portnum / bitfield,
-- outside the encoded payload) and enable request/response correlation and message
-- threading across mesh packets. init.sql already carries the columns for fresh
-- installs; this migration back-fills them on existing deployments so the Python
-- INSERT in DBHandler.store_mesh_packet_metrics keeps matching the live schema.

ALTER TABLE mesh_packet_metrics ADD COLUMN IF NOT EXISTS request_id BIGINT;
ALTER TABLE mesh_packet_metrics ADD COLUMN IF NOT EXISTS reply_id   BIGINT;
