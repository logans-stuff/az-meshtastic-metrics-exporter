#!/usr/bin/env python3
"""
Prune location data older than the configured privacy window.

Removes historical rows from position_metrics and clears the cached latest
location on node_details rows whose location_updated_at is older than the
retention window. node_details rows without a recorded location_updated_at
(legacy rows that predate migration 008) are left alone unless --force-legacy
is passed.

Usage:
    python scripts/prune_location_data.py --dry-run
    python scripts/prune_location_data.py

Connection options:
    DATABASE_URL     full psycopg connection string or postgres:// URL
    PG_HOST          localhost
    PG_PORT          5432
    PG_DB            meshtastic
    PG_USER          postgres
    PG_PASSWORD      postgres
"""

import argparse
import os
import sys


DEFAULT_RETENTION_DAYS = 30


def build_conninfo(args: argparse.Namespace) -> str:
    if args.database_url:
        return args.database_url

    env_database_url = os.getenv("DATABASE_URL")
    if env_database_url:
        return env_database_url

    return (
        f"host={os.getenv('PG_HOST', 'localhost')} "
        f"port={os.getenv('PG_PORT', '5432')} "
        f"dbname={os.getenv('PG_DB', 'meshtastic')} "
        f"user={os.getenv('PG_USER', 'postgres')} "
        f"password={os.getenv('PG_PASSWORD', 'postgres')}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Delete old position history and clear stale node_details locations."
    )
    parser.add_argument(
        "--retention-days",
        type=int,
        default=DEFAULT_RETENTION_DAYS,
        help=f"Number of days of location history to keep. Default: {DEFAULT_RETENTION_DAYS}.",
    )
    parser.add_argument(
        "--database-url",
        help="Override DATABASE_URL/PG_* environment variables.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show how many rows/nodes would change, then roll back.",
    )
    parser.add_argument(
        "--force-legacy",
        action="store_true",
        help=(
            "Also clear node_details locations whose location_updated_at is NULL. "
            "Migration 008 backfills this column, so NULL means the row predates "
            "the migration without a known location-write time. Off by default to "
            "avoid wiping legitimate cached locations on first run."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.retention_days < 1:
        print("--retention-days must be at least 1", file=sys.stderr)
        return 2

    try:
        import psycopg
    except ModuleNotFoundError:
        print(
            "Missing dependency: psycopg. Install project requirements before running this script.",
            file=sys.stderr,
        )
        return 1

    conninfo = build_conninfo(args)
    interval_text = f"{args.retention_days} days"

    stale_predicate = "nd.location_updated_at < NOW() - %s::INTERVAL"
    if args.force_legacy:
        stale_predicate = f"(nd.location_updated_at IS NULL OR {stale_predicate})"

    clear_stale_locations_sql = f"""
        WITH updated AS (
            UPDATE node_details nd
            SET latitude            = NULL,
                longitude           = NULL,
                altitude            = NULL,
                precision           = NULL,
                location_updated_at = NULL
            WHERE (
                nd.latitude IS NOT NULL
                OR nd.longitude IS NOT NULL
                OR nd.altitude IS NOT NULL
                OR nd.precision IS NOT NULL
            )
            AND {stale_predicate}
            RETURNING nd.node_id
        )
        SELECT COUNT(*) FROM updated;
    """

    delete_old_positions_sql = """
        WITH deleted AS (
            DELETE FROM position_metrics
            WHERE time < NOW() - %s::INTERVAL
            RETURNING 1
        )
        SELECT COUNT(*) FROM deleted;
    """

    try:
        with psycopg.connect(conninfo) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT COUNT(*) FROM position_metrics WHERE time < NOW() - %s::INTERVAL;",
                    (interval_text,),
                )
                old_position_rows = cur.fetchone()[0]

                cur.execute(clear_stale_locations_sql, (interval_text,))
                cleared_node_rows = cur.fetchone()[0]

                cur.execute(delete_old_positions_sql, (interval_text,))
                deleted_position_rows = cur.fetchone()[0]

            if args.dry_run:
                conn.rollback()
                action = "Would clear/delete"
            else:
                conn.commit()
                action = "Cleared/deleted"

    except psycopg.Error as exc:
        print(f"Database error: {exc}", file=sys.stderr)
        return 1

    print(f"{action} node_details locations: {cleared_node_rows}")
    print(f"{action} position_metrics rows: {deleted_position_rows}")
    if args.dry_run:
        print(f"Position rows older than {args.retention_days} days: {old_position_rows}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
