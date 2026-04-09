-- Migration to add ok_to_mqtt to mesh_packet_metrics

ALTER TABLE mesh_packet_metrics ADD COLUMN IF NOT EXISTS ok_to_mqtt BOOLEAN;
