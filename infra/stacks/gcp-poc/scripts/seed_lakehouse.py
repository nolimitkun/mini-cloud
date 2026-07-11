#!/usr/bin/env python3
"""Seed the lakehouse with sample data and expose it via the Iceberg REST catalog.

Creates one Iceberg table per dataset (sales / users / logs) through the BigLake
Lakehouse Runtime Catalog — the same REST endpoint Spark, Trino, Flink and
PyIceberg use — and appends generated rows. Tables land under the matching
managed folder in the data bucket (gs://<bucket>/<dataset>/<table>).

Auth: uses your gcloud user credentials. The caller needs BigLake catalog access
on the spoke project and write access to the data bucket (the deployment's
managed-folder IAM already covers the vending SAs; a project owner/editor also
works directly).

Usage:
    pip install -r requirements.txt
    python seed_lakehouse.py \
        --project mini-cloud-lakehouse \
        --bucket  mini-cloud-lakehouse-data
    # --recreate  drop and rebuild tables instead of skipping populated ones

Idempotent by default: a table that already has rows is left untouched.
"""
from __future__ import annotations

import argparse
import datetime as dt
import random
import subprocess
import sys

import pyarrow as pa
from pyiceberg.catalog.rest import RestCatalog
from pyiceberg.schema import Schema
from pyiceberg.types import (
    BooleanType,
    DateType,
    DoubleType,
    IntegerType,
    LongType,
    NestedField,
    StringType,
    TimestampType,
)

REST_URI = "https://biglake.googleapis.com/iceberg/v1/restcatalog"


def gcloud_token() -> str:
    try:
        return subprocess.check_output(
            ["gcloud", "auth", "print-access-token"], text=True
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        sys.exit(f"could not get gcloud access token: {exc}")


def build_datasets() -> list[tuple[str, Schema, list[dict]]]:
    """Return (table identifier, Iceberg schema, rows) for each dataset."""
    random.seed(42)
    base = dt.datetime(2026, 7, 1, 8, 0, 0)

    sales_schema = Schema(
        NestedField(1, "order_id", LongType()),
        NestedField(2, "order_ts", TimestampType()),
        NestedField(3, "product", StringType()),
        NestedField(4, "quantity", IntegerType()),
        NestedField(5, "unit_price", DoubleType()),
        NestedField(6, "region", StringType()),
    )
    products = ["widget", "gadget", "sprocket", "cog", "gizmo"]
    regions = ["EU-West", "EU-North", "US-East", "APAC"]
    sales_rows = [
        {
            "order_id": 1000 + i,
            "order_ts": base + dt.timedelta(minutes=17 * i),
            "product": random.choice(products),
            "quantity": random.randint(1, 20),
            "unit_price": round(random.uniform(4.5, 199.9), 2),
            "region": random.choice(regions),
        }
        for i in range(40)
    ]

    users_schema = Schema(
        NestedField(1, "user_id", LongType()),
        NestedField(2, "name", StringType()),
        NestedField(3, "email", StringType()),
        NestedField(4, "country", StringType()),
        NestedField(5, "signup_date", DateType()),
        NestedField(6, "active", BooleanType()),
    )
    countries = ["FR", "DE", "NL", "US", "JP", "SG"]
    firsts = ["alice", "bob", "carol", "dan", "erin", "frank", "grace", "heidi"]
    users_rows = [
        {
            "user_id": 1 + i,
            "name": f"{random.choice(firsts)}_{i}",
            "email": f"user{i}@example.com",
            "country": random.choice(countries),
            "signup_date": dt.date(2025, 1, 1) + dt.timedelta(days=random.randint(0, 550)),
            "active": random.random() > 0.25,
        }
        for i in range(25)
    ]

    logs_schema = Schema(
        NestedField(1, "log_id", LongType()),
        NestedField(2, "event_ts", TimestampType()),
        NestedField(3, "level", StringType()),
        NestedField(4, "service", StringType()),
        NestedField(5, "latency_ms", IntegerType()),
        NestedField(6, "message", StringType()),
    )
    levels = ["INFO", "INFO", "INFO", "WARN", "ERROR", "DEBUG"]
    services = ["api-gateway", "auth-svc", "billing", "ingest", "catalog"]
    codes = [200, 200, 200, 404, 500, 503]
    logs_rows = [
        {
            "log_id": 500000 + i,
            "event_ts": base + dt.timedelta(seconds=31 * i),
            "level": random.choice(levels),
            "service": random.choice(services),
            "latency_ms": random.randint(2, 1200),
            "message": f"request handled code={random.choice(codes)}",
        }
        for i in range(60)
    ]

    return [
        ("sales.orders", sales_schema, sales_rows),
        ("users.profiles", users_schema, users_rows),
        ("logs.events", logs_schema, logs_rows),
    ]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--project", default="mini-cloud-lakehouse", help="spoke project id")
    ap.add_argument("--bucket", default="mini-cloud-lakehouse-data", help="data bucket / catalog name")
    ap.add_argument("--recreate", action="store_true", help="drop and rebuild each table")
    args = ap.parse_args()

    # X-Iceberg-Access-Delegation makes the catalog vend downscoped GCS credentials
    # in table responses, so FileIO reads/writes work with only roles/biglake.viewer
    # (no direct GCS IAM). Without it, PyIceberg falls back to the caller's own
    # credentials, which only works for identities that can reach the bucket directly.
    catalog = RestCatalog(
        "lakehouse",
        uri=REST_URI,
        warehouse=f"gs://{args.bucket}",
        token=gcloud_token(),
        **{
            "header.x-goog-user-project": args.project,
            "header.X-Iceberg-Access-Delegation": "vended-credentials",
        },
    )

    for identifier, schema, rows in build_datasets():
        namespace = identifier.split(".")[0]
        if (namespace,) not in catalog.list_namespaces():
            catalog.create_namespace(namespace)

        exists = catalog.table_exists(identifier)
        if exists and args.recreate:
            catalog.drop_table(identifier)
            exists = False
        elif exists:
            table = catalog.load_table(identifier)
            count = table.scan().to_arrow().num_rows
            if count:
                print(f"{identifier:16s} -> skipped (already has {count} rows)")
                continue

        table = catalog.load_table(identifier) if exists else catalog.create_table(identifier, schema=schema)
        table.append(pa.Table.from_pylist(rows, schema=schema.as_arrow()))
        count = table.scan().to_arrow().num_rows
        print(f"{identifier:16s} -> {count} rows @ {table.metadata.location}")

    print("\nExposed via runtime catalog:", REST_URI)
    for namespace in ("sales", "users", "logs"):
        print(f"  {namespace}:", [".".join(t) for t in catalog.list_tables(namespace)])


if __name__ == "__main__":
    main()
