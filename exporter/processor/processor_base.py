import base64
import json
import logging
import os
import sys

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

try:
    from meshtastic.protobuf.mesh_pb2 import MeshPacket, Data, HardwareModel
    from meshtastic.protobuf.portnums_pb2 import PortNum
    from meshtastic.protobuf.mqtt_pb2 import ServiceEnvelope
except ImportError:
    from meshtastic.mesh_pb2 import MeshPacket, Data, HardwareModel
    from meshtastic.portnums_pb2 import PortNum
    from meshtastic.mqtt_pb2 import ServiceEnvelope

from psycopg_pool import ConnectionPool

from exporter.client_details import ClientDetails
from exporter.db_handler import DBHandler
from exporter.processor.processors import ProcessorRegistry


class MessageProcessor:
    def __init__(self, db_pool: ConnectionPool):
        self.db_pool = db_pool
        self.db_handler = DBHandler(db_pool)
        self.processor_registry = ProcessorRegistry()


    @staticmethod
    def process_json_mqtt(message):
        topic = message.topic
        json_packet = json.loads(message.payload)
        if 'sender' in json_packet:
            if json_packet['sender'][0] == '!':
                gateway_node_id = str(int(json_packet['sender'][1:], 16))
                # Node configuration update is now handled by the database timestamps

    @staticmethod
    def process_mqtt(topic: str, service_envelope: ServiceEnvelope, mesh_packet: MeshPacket):
        is_encrypted = False
        if getattr(mesh_packet, 'encrypted'):
            is_encrypted = True
        if getattr(service_envelope, 'gateway_id'):
            if service_envelope.gateway_id[0] == '!':
                gateway_node_id = str(int(service_envelope.gateway_id[1:], 16))
                # Node configuration update is now handled by the database timestamps

    @staticmethod
    def extract_channel_from_topic(topic: str) -> str:
        topic_parts = topic.split('/')
        known_channels = {
            'longfast', 'mediumfast', 'shortfast', 'longslow', 'shortslow', 'mediumslow',
            'verylongslow', 'verylongfast'
        }
        for part in topic_parts:
            normalized = ''.join(ch for ch in part.lower() if ch.isalnum())
            if normalized in known_channels:
                return normalized
        return None

    def update_node_heard_on(self, node_id: str, topic: str):
        channel = self.extract_channel_from_topic(topic)
        with self.db_pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE node_details
                    SET last_heard_topic = %s,
                        last_heard_channel = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE node_id = %s
                """, (topic, channel, node_id))
                conn.commit()

    def process(self, mesh_packet: MeshPacket, reporting_gateway: str = None, topic: str = None):
        try:
            if getattr(mesh_packet, 'encrypted'):
                key_bytes = base64.b64decode(os.getenv('MQTT_SERVER_KEY', '1PG7OiApB1nwvP+rz05pAQ==').encode('ascii'))
                nonce_packet_id = getattr(mesh_packet, "id").to_bytes(8, "little")
                nonce_from_node = getattr(mesh_packet, "from").to_bytes(8, "little")

                # Put both parts into a single byte array.
                nonce = nonce_packet_id + nonce_from_node

                cipher = Cipher(algorithms.AES(key_bytes), modes.CTR(nonce), backend=default_backend())
                decryptor = cipher.decryptor()
                decrypted_bytes = decryptor.update(getattr(mesh_packet, "encrypted")) + decryptor.finalize()

                data = Data()
                try:
                    data.ParseFromString(decrypted_bytes)
                except Exception as e:
                    logging.warning(
                        f"Failed to decrypt message from node {getattr(mesh_packet, 'from', 'unknown')} (hex: {getattr(mesh_packet, 'from', 'unknown'):x}) with packet ID {getattr(mesh_packet, 'id', 'unknown')}: {e}")
                    return
                mesh_packet.decoded.CopyFrom(data)
            port_num = int(mesh_packet.decoded.portnum)
            payload = mesh_packet.decoded.payload

            source_node_id = getattr(mesh_packet, 'from')
            source_client_details = self._get_client_details(source_node_id)
            if topic:
                self.update_node_heard_on(source_client_details.node_id, topic)
            if os.getenv('MESH_HIDE_SOURCE_DATA', 'false') == 'true':
                source_client_details = ClientDetails(node_id=source_client_details.node_id, short_name='Hidden',
                                                      long_name='Hidden')

            destination_node_id = getattr(mesh_packet, 'to')
            destination_client_details = self._get_client_details(destination_node_id)
            if os.getenv('MESH_HIDE_DESTINATION_DATA', 'false') == 'true':
                destination_client_details = ClientDetails(node_id=destination_client_details.node_id,
                                                           short_name='Hidden',
                                                           long_name='Hidden')

            self.process_simple_packet_details(destination_client_details, mesh_packet, port_num, source_client_details, reporting_gateway)

            processor = ProcessorRegistry.get_processor(port_num)(self.db_pool)
            processor.process(payload, client_details=source_client_details, mesh_packet=mesh_packet, reporting_gateway=reporting_gateway)
        except Exception as e:
            logging.warning(f"Failed to process message: {e}")
            return

    @staticmethod
    def get_port_name_from_portnum(port_num):
        descriptor = PortNum.DESCRIPTOR
        for enum_value in descriptor.values:
            if enum_value.number == port_num:
                return enum_value.name
        return 'UNKNOWN_PORT'

    def process_simple_packet_details(self, destination_client_details, mesh_packet: MeshPacket, port_num,
                                      source_client_details, reporting_gateway: str = None):
        # Resolve transport_mechanism enum to its name string
        transport_name = None
        transport_val = getattr(mesh_packet, 'transport_mechanism', None)
        if transport_val is not None:
            descriptor = mesh_packet.DESCRIPTOR.fields_by_name.get('transport_mechanism')
            if descriptor and descriptor.enum_type:
                enum_val = descriptor.enum_type.values_by_number.get(transport_val)
                transport_name = enum_val.name if enum_val else str(transport_val)

        request_id = getattr(mesh_packet.decoded, 'request_id', 0) or None
        reply_id = getattr(mesh_packet.decoded, 'reply_id', 0) or None

        # Store mesh packet metrics in TimescaleDB
        self.db_handler.store_mesh_packet_metrics(
            source_client_details.node_id,
            destination_client_details.node_id,
            {
                'portnum': self.get_port_name_from_portnum(port_num),
                'request_id': request_id,
                'reply_id': reply_id,
                'packet_id': mesh_packet.id,
                'channel': mesh_packet.channel,
                'rx_time': mesh_packet.rx_time,
                'rx_snr': mesh_packet.rx_snr,
                'rx_rssi': mesh_packet.rx_rssi,
                'hop_limit': mesh_packet.hop_limit,
                'hop_start': mesh_packet.hop_start,
                'want_ack': mesh_packet.want_ack,
                'via_mqtt': mesh_packet.via_mqtt,
                'message_size_bytes': sys.getsizeof(mesh_packet),
                'relay_node': getattr(mesh_packet, 'relay_node', None) or None,
                'next_hop': getattr(mesh_packet, 'next_hop', None) or None,
                'transport_mechanism': transport_name,
                'pki_encrypted': getattr(mesh_packet, 'pki_encrypted', False),
                'reporting_gateway': reporting_gateway,
            }
        )

    def _get_client_details(self, node_id: int) -> ClientDetails:
        if node_id == 4294967295 or node_id == 1:  # FFFFFFFF or 1 (Broadcast)
            node_id_str = str(node_id)
            # Insert the broadcast node into node_details if it doesn't exist
            with self.db_pool.connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                                INSERT INTO node_details (node_id, short_name, long_name, hardware_model, role)
                                VALUES (%s, %s, %s, %s, %s)
                                ON CONFLICT (node_id) DO NOTHING
                                """, (node_id_str, 'Broadcast', 'Broadcast', 'BROADCAST', 'BROADCAST'))
                    conn.commit()
            return ClientDetails(node_id=node_id_str, short_name='Broadcast', long_name='Broadcast')
        node_id_str = str(node_id)  # Convert the integer to a string
        with self.db_pool.connection() as conn:
            with conn.cursor() as cur:
                # First, try to select the existing record
                cur.execute("""
                    SELECT node_id, short_name, long_name, hardware_model, role 
                    FROM node_details 
                    WHERE node_id = %s;
                """, (node_id_str,))
                result = cur.fetchone()

                if not result:
                    # If the client is not found, insert a new record
                    cur.execute("""
                        INSERT INTO node_details (node_id, short_name, long_name, hardware_model, role)
                        VALUES (%s, %s, %s, %s, %s)
                        RETURNING node_id, short_name, long_name, hardware_model, role;
                    """, (node_id_str, 'Unknown', 'Unknown', HardwareModel.UNSET, None))
                    conn.commit()
                    result = cur.fetchone()

        # At this point, we should always have a result, either from SELECT or INSERT
        return ClientDetails(
            node_id=result[0],
            short_name=result[1],
            long_name=result[2],
            hardware_model=result[3],
            role=result[4]
        )
