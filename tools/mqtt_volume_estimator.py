import os
import time
import paho.mqtt.client as mqtt
from dotenv import load_dotenv

try:
    from meshtastic.mesh_pb2 import MeshPacket
    from meshtastic.mqtt_pb2 import ServiceEnvelope
except ImportError:
    from meshtastic.protobuf.mesh_pb2 import MeshPacket
    from meshtastic.protobuf.mqtt_pb2 import ServiceEnvelope

load_dotenv()

# Trackers for our estimation
unique_packets = set()
total_observations = set()

# Settings
SAMPLE_DURATION_SECONDS = 60
start_time = None

def handle_connect(client, userdata, flags, reason_code, properties):
    topics = os.getenv('MQTT_TOPIC', 'msh/israel/#').split(',')
    topics_tuples = [(topic, 0) for topic in topics]
    err, code = client.subscribe(topics_tuples)
    if err:
        print(f"Error subscribing: {err} code: {code}")

def handle_message(client, userdata, message):
    if '/json/' in message.topic or '/stat/' in message.topic or '/tele/' in message.topic:
        return

    try:
        envelope = ServiceEnvelope()
        envelope.ParseFromString(message.payload)
        packet: MeshPacket = envelope.packet
        
        # Original deductive Logic (Before): Only ever counted the core packet.id
        unique_packets.add(str(packet.id))
        
        # New logging logic (After): Includes the gateway ID so multiple gates can report the same packet.id
        topic_parts = message.topic.split('/')
        reporting_gateway_id = None
        if topic_parts and topic_parts[-1].startswith('!'):
            try:
                reporting_gateway_id = str(int(topic_parts[-1][1:], 16))
            except ValueError:
                pass
                
        observation_id = f"{packet.id}_{reporting_gateway_id}"
        total_observations.add(observation_id)
        
    except Exception as e:
        pass

if __name__ == "__main__":
    print(f"Starting MQTT volume estimator. Listening to the firehose for {SAMPLE_DURATION_SECONDS} seconds...")
    mqtt_client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        protocol=mqtt.MQTTv5
    )
    mqtt_client.on_connect = handle_connect
    mqtt_client.on_message = handle_message

    if os.getenv('MQTT_IS_TLS', 'false').lower() == 'true':
        tls_context = mqtt.ssl.create_default_context()
        mqtt_client.tls_set_context(tls_context)

    if os.getenv('MQTT_USERNAME', None) and os.getenv('MQTT_PASSWORD', None):
        mqtt_client.username_pw_set(os.getenv('MQTT_USERNAME'), os.getenv('MQTT_PASSWORD'))

    try:
        mqtt_client.connect(
            os.getenv('MQTT_HOST', 'localhost'),
            int(os.getenv('MQTT_PORT', 1883)),
            keepalive=60,
        )
    except Exception as e:
        print(f"Failed to connect to MQTT broker: {e}")
        exit(1)
        
    mqtt_client.loop_start()
    
    # Wait for the sampling window to complete
    try:
        time.sleep(SAMPLE_DURATION_SECONDS)
    except KeyboardInterrupt:
        print("\nStopping early...")
        
    mqtt_client.loop_stop()
    mqtt_client.disconnect()
    
    print("\n" + "="*50)
    print("      MQTT VOLUME ESTIMATION RESULTS")
    print("="*50)
    print(f"Sample Duration: {SAMPLE_DURATION_SECONDS} seconds")
    print(f"Total Unique Packets Transmitted: {len(unique_packets)}")
    print(f"Total Combined Gateway Overhears: {len(total_observations)}")
    
    if len(unique_packets) > 0:
        ratio = len(total_observations) / len(unique_packets)
        print(f"\nAverage gateways capturing a single packet: {ratio:.1f}x")
        
        # Calculate dailies
        multiplier = 86400 / SAMPLE_DURATION_SECONDS
        estimated_daily_old = len(unique_packets) * multiplier
        estimated_daily_new = len(total_observations) * multiplier
        
        print("\n--- Estimated Daily Database Ingest ---")
        print(f"BEFORE (Duplicate Overhears Dropped): ~{int(estimated_daily_old):,} rows/day")
        print(f"AFTER (All Overhears Stored):         ~{int(estimated_daily_new):,} rows/day")
    else:
        print("\nNo protobuf packets captured during the sampling window.")
