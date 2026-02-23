#!/usr/bin/env python3
"""
Migration script: Prometheus → TimescaleDB

Migrates the last 30 days of Meshtastic metrics from a Prometheus instance
into TimescaleDB. Run this once after switching stacks.

WARNING: This script performs plain INSERTs. Running it more than once on the
same time range will create duplicate rows in TimescaleDB since the hypertables
have no unique constraint on (time, node_id).

Usage:
    pip install psycopg[binary]
    python scripts/migrate_prometheus_to_timescale.py

Environment variables (all optional, shown with defaults):
    PROMETHEUS_URL   http://localhost:9090
    STEP             60s   (query resolution — increase to reduce duplicate rows)
    DAYS             30    (how many days back to migrate)
    PG_HOST          localhost
    PG_PORT          5432
    PG_DB            meshtastic
    PG_USER          postgres
    PG_PASSWORD      postgres
"""

import math
import os
import sys
import json
import urllib.request
import urllib.parse
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Tuple, Optional

import psycopg

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PROMETHEUS_URL = os.getenv("PROMETHEUS_URL", "http://localhost:9090")
STEP = os.getenv("STEP", "60s")
DAYS = int(os.getenv("DAYS", "30"))
CHUNK_DAYS = 7  # query Prometheus in weekly chunks to avoid timeouts

PG_CONNINFO = (
    f"host={os.getenv('PG_HOST', 'localhost')} "
    f"port={os.getenv('PG_PORT', '5432')} "
    f"dbname={os.getenv('PG_DB', 'meshtastic')} "
    f"user={os.getenv('PG_USER', 'postgres')} "
    f"password={os.getenv('PG_PASSWORD', 'postgres')}"
)

# ---------------------------------------------------------------------------
# Prometheus metric → TimescaleDB column mappings
# ---------------------------------------------------------------------------

DEVICE_METRICS: Dict[str, str] = {
    "telemetry_app_battery_level": "battery_level",
    "telemetry_app_voltage": "voltage",
    "telemetry_app_channel_utilization": "channel_utilization",
    "telemetry_app_air_util_tx": "air_util_tx",
    "telemetry_app_uptime_seconds": "uptime_seconds",
}

ENVIRONMENT_METRICS: Dict[str, str] = {
    "telemetry_app_temperature": "temperature",
    "telemetry_app_relative_humidity": "relative_humidity",
    "telemetry_app_barometric_pressure": "barometric_pressure",
    "telemetry_app_gas_resistance": "gas_resistance",
    "telemetry_app_iaq": "iaq",
    "telemetry_app_distance": "distance",
    "telemetry_app_lux": "lux",
    "telemetry_app_white_lux": "white_lux",
    "telemetry_app_ir_lux": "ir_lux",
    "telemetry_app_uv_lux": "uv_lux",
    "telemetry_app_wind_direction": "wind_direction",
    "telemetry_app_wind_speed": "wind_speed",
    "telemetry_app_weight": "weight",
}

AIR_QUALITY_METRICS: Dict[str, str] = {
    "telemetry_app_pm10_standard": "pm10_standard",
    "telemetry_app_pm25_standard": "pm25_standard",
    "telemetry_app_pm100_standard": "pm100_standard",
    "telemetry_app_pm10_environmental": "pm10_environmental",
    "telemetry_app_pm25_environmental": "pm25_environmental",
    "telemetry_app_pm100_environmental": "pm100_environmental",
    "telemetry_app_particles_03um": "particles_03um",
    "telemetry_app_particles_05um": "particles_05um",
    "telemetry_app_particles_10um": "particles_10um",
    "telemetry_app_particles_25um": "particles_25um",
    "telemetry_app_particles_50um": "particles_50um",
    "telemetry_app_particles_100um": "particles_100um",
}

POWER_METRICS: Dict[str, str] = {
    "telemetry_app_ch1_voltage": "ch1_voltage",
    "telemetry_app_ch1_current": "ch1_current",
    "telemetry_app_ch2_voltage": "ch2_voltage",
    "telemetry_app_ch2_current": "ch2_current",
    "telemetry_app_ch3_voltage": "ch3_voltage",
    "telemetry_app_ch3_current": "ch3_current",
}

PAX_METRICS: Dict[str, str] = {
    "pax_wifi": "wifi_stations",
    "pax_ble": "ble_beacons",
}

ALL_GROUPS = {
    "device_metrics": DEVICE_METRICS,
    "environment_metrics": ENVIRONMENT_METRICS,
    "air_quality_metrics": AIR_QUALITY_METRICS,
    "power_metrics": POWER_METRICS,
    "pax_counter_metrics": PAX_METRICS,
}

# ---------------------------------------------------------------------------
# Prometheus helpers
# ---------------------------------------------------------------------------

def prom_query_range(metric: str, start: datetime, end: datetime) -> List[dict]:
    """Call Prometheus query_range API, return list of series dicts."""
    params = urllib.parse.urlencode({
        "query": metric,
        "start": f"{start.timestamp():.3f}",
        "end": f"{end.timestamp():.3f}",
        "step": STEP,
    })
    url = f"{PROMETHEUS_URL}/api/v1/query_range?{params}"
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            data = json.loads(resp.read())
    except Exception as exc:
        raise RuntimeError(f"Prometheus request failed for {metric}: {exc}") from exc

    if data.get("status") != "success":
        raise RuntimeError(f"Prometheus error for {metric}: {data.get('error', data)}")

    return data["data"]["result"]


# ---------------------------------------------------------------------------
# Data transformation
# ---------------------------------------------------------------------------

def collect_group(
    metric_map: Dict[str, str],
    start: datetime,
    end: datetime,
) -> Tuple[Dict[Tuple[str, float], dict], Dict[str, dict]]:
    """
    Query all metrics in a group from Prometheus and merge by (node_id, ts).

    Returns:
        rows   — dict keyed by (node_id, unix_ts) → {col: value, ...}
        nodes  — dict keyed by node_id → node_details fields
    """
    rows: Dict[Tuple[str, float], dict] = defaultdict(dict)
    nodes: Dict[str, dict] = {}

    for prom_name, col in metric_map.items():
        try:
            series_list = prom_query_range(prom_name, start, end)
        except RuntimeError as exc:
            print(f"    warn: {exc}")
            continue

        for series in series_list:
            labels = series["metric"]
            node_id = labels.get("node_id")
            if not node_id:
                continue

            # Collect node metadata from labels (first occurrence wins)
            if node_id not in nodes:
                nodes[node_id] = {
                    "node_id": node_id,
                    "short_name": labels.get("short_name"),
                    "long_name": labels.get("long_name"),
                    "hardware_model": labels.get("hardware_model"),
                    "role": labels.get("role"),
                }

            for ts, raw_value in series["values"]:
                try:
                    value = float(raw_value)
                    if math.isnan(value) or math.isinf(value):
                        continue
                except (ValueError, TypeError):
                    continue

                key = (node_id, float(ts))
                rows[key]["node_id"] = node_id
                rows[key]["time"] = datetime.fromtimestamp(float(ts), tz=timezone.utc)
                rows[key][col] = value

    return rows, nodes


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def upsert_nodes(cur: psycopg.Cursor, nodes: Dict[str, dict]) -> None:
    if not nodes:
        return
    cur.executemany(
        """
        INSERT INTO node_details (node_id, short_name, long_name, hardware_model, role)
        VALUES (%(node_id)s, %(short_name)s, %(long_name)s, %(hardware_model)s, %(role)s)
        ON CONFLICT (node_id) DO UPDATE SET
            short_name     = COALESCE(EXCLUDED.short_name,     node_details.short_name),
            long_name      = COALESCE(EXCLUDED.long_name,      node_details.long_name),
            hardware_model = COALESCE(EXCLUDED.hardware_model, node_details.hardware_model),
            role           = COALESCE(EXCLUDED.role,           node_details.role),
            updated_at     = NOW()
        """,
        list(nodes.values()),
    )


def bulk_insert(
    cur: psycopg.Cursor,
    table: str,
    columns: List[str],
    rows: Dict,
) -> int:
    """
    Bulk-insert merged rows into a TimescaleDB hypertable using COPY.
    Returns number of rows written.
    """
    if not rows:
        return 0

    all_cols = ["time", "node_id"] + columns
    col_list = ", ".join(all_cols)

    records: List[tuple] = []
    for row in rows.values():
        if "time" not in row or "node_id" not in row:
            continue
        records.append(tuple(row.get(c) for c in all_cols))

    if not records:
        return 0

    with cur.copy(f"COPY {table} ({col_list}) FROM STDIN") as copy:
        for record in records:
            copy.write_row(record)

    return len(records)


# ---------------------------------------------------------------------------
# Main migration
# ---------------------------------------------------------------------------

def make_chunks(start: datetime, end: datetime) -> List[Tuple[datetime, datetime]]:
    chunks = []
    chunk_start = start
    while chunk_start < end:
        chunk_end = min(chunk_start + timedelta(days=CHUNK_DAYS), end)
        chunks.append((chunk_start, chunk_end))
        chunk_start = chunk_end
    return chunks


def migrate() -> None:
    now = datetime.now(tz=timezone.utc)
    start = now - timedelta(days=DAYS)

    print("=" * 60)
    print("Prometheus → TimescaleDB migration")
    print(f"  Range : {start.date()} → {now.date()} ({DAYS} days)")
    print(f"  Step  : {STEP}")
    print(f"  Source: {PROMETHEUS_URL}")
    print("=" * 60)
    print()

    table_columns = {
        "device_metrics": list(DEVICE_METRICS.values()),
        "environment_metrics": list(ENVIRONMENT_METRICS.values()),
        "air_quality_metrics": list(AIR_QUALITY_METRICS.values()),
        "power_metrics": list(POWER_METRICS.values()),
        "pax_counter_metrics": list(PAX_METRICS.values()),
    }

    chunks = make_chunks(start, now)

    with psycopg.connect(PG_CONNINFO, autocommit=False) as conn:
        with conn.cursor() as cur:
            for table, metric_map in ALL_GROUPS.items():
                print(f"[{table}]")
                total_rows = 0
                total_nodes: Dict[str, dict] = {}

                for chunk_start, chunk_end in chunks:
                    print(
                        f"  {chunk_start.date()} → {chunk_end.date()} ...",
                        end="  ",
                        flush=True,
                    )
                    rows, nodes = collect_group(metric_map, chunk_start, chunk_end)
                    total_nodes.update(nodes)

                    upsert_nodes(cur, nodes)
                    n = bulk_insert(cur, table, table_columns[table], rows)
                    conn.commit()

                    print(f"{n:,} rows")
                    total_rows += n

                print(f"  → {total_rows:,} total rows, {len(total_nodes)} node(s)\n")

    print("Migration complete.")


if __name__ == "__main__":
    try:
        migrate()
    except KeyboardInterrupt:
        print("\nAborted.")
        sys.exit(1)
    except Exception as exc:
        print(f"\nFatal: {exc}", file=sys.stderr)
        sys.exit(1)
