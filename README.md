# Meshtastic Metrics Exporter
[![CodeQL](https://github.com/tcivie/meshtastic-metrics-exporter/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/tcivie/meshtastic-metrics-exporter/actions/workflows/github-code-scanning/codeql)

The `meshtastic-metrics-exporter` is a tool designed to collect and store comprehensive data from Meshtastic MQTT servers into TimescaleDB, with pre-configured Grafana dashboards for visualization and analysis.

## Public Dashboards

You can explore these public instances to see the exporter in action:

- **Canadaverse Dashboard**: [dash.mt.gt](https://dash.mt.gt) (Guest access: username: `guest`, password: `guest`)
  > This instance demonstrates the metrics exporter's capabilities in a production environment, maintained by [@tb0hdan](https://github.com/tb0hdan).

## Features

- Ingests nearly all packet types from Meshtastic MQTT servers
- Stores time-series metrics in TimescaleDB hypertables for efficient querying
- Tracks node details, telemetry, and network topology in PostgreSQL tables
- Comes with pre-configured Grafana dashboards for immediate visualization
- Automatic data retention policies and continuous aggregations
- Configuration via `.env` file

## Deployment

### Recommended Hosting

For affordable and reliable hosting, I personally use [Hetzner Cloud](https://hetzner.cloud/?ref=iMFSvXv8FFMJ) for running this project. Their VPS offerings provide excellent performance for TimescaleDB and Grafana workloads at competitive prices.

*Note: This is a referral link - using it supports the project at no extra cost to you. Plus you should get free 20$ for use*

### Database Structure

The system uses PostgreSQL with TimescaleDB extension:

#### Regular Tables

1. **messages** - Deduplication table with auto-expiry
2. **node_details** - Node information (ID, names, hardware, location, MQTT status, last-heard MQTT topic/channel, direct MQTT topic)
3. **node_neighbors** - Network topology from NeighborInfo packets
4. **node_configurations** - Module configurations and update intervals

#### TimescaleDB Hypertables (Time-Series Data)

1. **device_metrics** - Battery, voltage, channel utilization, uptime
2. **environment_metrics** - Temperature, humidity, pressure, air quality sensors
3. **air_quality_metrics** - Particulate matter measurements
4. **power_metrics** - Multi-channel voltage/current measurements
5. **pax_counter_metrics** - WiFi and BLE device counts
6. **mesh_packet_metrics** - Packet routing and network statistics
7. **position_metrics** - Historical GPS coordinates for recent location analysis

All hypertables have:
- Automatic retention policies
- Indexes optimized for time-series queries
- Continuous aggregation support

Default retention is 3 months for non-location hypertables and 30 days for
`position_metrics`. The shorter location window is intentional:
`node_details` stores the latest coordinate for dashboard maps, so run the
location pruning script below if you also want stale latest-location fields
cleared.

### Grafana Dashboards

The project includes several pre-configured dashboards:

#### Main Dashboard
<img width="1470" alt="image" src="https://github.com/user-attachments/assets/09fe72e5-23eb-4516-9f34-19e2cc38b7dc">

Shows network overview, active nodes, packet statistics, and channel utilization.

**Note:** Dashboard links target `localhost:3000`. Update panel configurations to match your Grafana server address.

#### Node Dashboard
![image](https://github.com/user-attachments/assets/d344b7dd-dadc-4cbe-84cc-44333ea6e0c4)

Detailed view per node with telemetry, battery metrics, and configuration details.

#### Network Graph
<img width="585" alt="SCR-20240707-qjaj" src="https://github.com/tcivie/meshtastic-metrics-exporter/assets/87943721/d29b2ac4-6291-4095-9938-e6e63df15098">

Visualizes mesh topology from NeighborInfo packets with SNR-based coloring:
- **Green nodes**: Connected to MQTT
- **Red nodes**: Disconnected from MQTT  
- **Gray nodes**: Unknown status (never connected)
- **Line colors**: Signal strength (SNR)

**Recommendation:** Allow 24 hours for data collection before expecting meaningful insights.

## Configuration

Configure the exporter using a `.env` file:
```dotenv
# TimescaleDB connection
DATABASE_URL=postgres://postgres:postgres@timescaledb:5432/meshtastic

# MQTT connection
MQTT_HOST=mqtt.meshtastic.org
MQTT_PORT=1883
MQTT_USERNAME=meshdev
MQTT_PASSWORD=large4cats
MQTT_KEEPALIVE=60
MQTT_TOPIC='msh/US/#'
MQTT_IS_TLS=false

# MQTT protocol version (MQTTv311 for public server)
# Options: MQTTv311, MQTTv31, MQTTv5
MQTT_PROTOCOL=MQTTv311

# MQTT callback API version
# Options: VERSION1, VERSION2
MQTT_CALLBACK_API_VERSION=VERSION2

# Exporter configuration
MESH_HIDE_SOURCE_DATA=false
MESH_HIDE_DESTINATION_DATA=false
MQTT_SERVER_KEY=1PG7OiApB1nwvP+rz05pAQ==

# Message types to filter (comma-separated)
# Full list: https://buf.build/meshtastic/protobufs/docs/main:meshtastic#meshtastic.PortNum
EXPORTER_MESSAGE_TYPES_TO_FILTER=

# Enable node configurations report
REPORT_NODE_CONFIGURATIONS=true

# Logging configuration
ENABLE_STREAM_HANDLER=true
LOG_LEVEL=INFO
LOG_FILE_MAX_SIZE=10MB
LOG_FILE_BACKUP_COUNT=5
```

## Running the Project

Start all services with Docker Compose:
```bash
docker compose up -d
```

This starts:
- **Exporter**: Python service processing MQTT messages
- **TimescaleDB**: PostgreSQL with TimescaleDB extension
- **Grafana**: Visualization platform (accessible at `http://localhost:3000`)

## Architecture
```
MQTT Server → Exporter (Python) → TimescaleDB → Grafana
```

The exporter:
1. Subscribes to Meshtastic MQTT topics
2. Decrypts encrypted packets (if key provided)
3. Parses Protocol Buffer messages
4. Stores metrics in TimescaleDB hypertables
5. Updates node details and topology in PostgreSQL tables

## Patching an Existing Deployment

To re-roll the exporter container with updated files (copy new files over old, remove old container/images, rebuild, recreate, then run DB migration):

```bash
./scripts/patch_node_topic_channel_tracking.sh
```

You can also target another compose project directory:

```bash
./scripts/patch_node_topic_channel_tracking.sh /path/to/meshtastic-metrics-exporter
```

### Database-only commands

If you only need to apply the schema update manually, run:

```bash
docker exec -i <timescaledb_container> psql -U postgres -d meshtastic \
  -f /dev/stdin < docker/timescaledb/008_retention_and_location_privacy.sql
```

To verify:

```bash
docker exec -it <timescaledb_container> psql -U postgres -d meshtastic \
  -c "SELECT hypertable_name, config FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' ORDER BY hypertable_name"
```

### Location privacy pruning

TimescaleDB retention automatically removes old `position_metrics` chunks, but
the latest location stored in `node_details` lingers so dashboard maps still
have something to render. To clear location data older than 30 days, run:

```bash
python scripts/prune_location_data.py --dry-run
python scripts/prune_location_data.py
```

The script uses `node_details.location_updated_at` (added in migration 008) to
decide which cached locations are stale, so apply the migration first. Rows
that predate the migration without a backfilled timestamp are left alone by
default; pass `--force-legacy` to clear them too.

Install the project requirements first if `psycopg` is not available. For
host-based runs, set `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, and
`PG_PASSWORD` as needed. To keep a different window, pass `--retention-days 90`.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on GitHub.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
