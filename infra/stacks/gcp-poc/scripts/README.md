# Lakehouse seed data

`seed_lakehouse.py` populates the lakehouse with sample data and exposes it
through the **Lakehouse Runtime Catalog** (the BigLake Iceberg REST catalog),
so any Iceberg engine — Spark, Trino, Flink, PyIceberg — can read it.

It creates one Iceberg table per dataset, each under its matching managed folder:

| Dataset | Table | Rows | Location |
|---|---|---|---|
| `sales` | `sales.orders` | 40 | `gs://<bucket>/sales/orders` |
| `users` | `users.profiles` | 25 | `gs://<bucket>/users/profiles` |
| `logs` | `logs.events` | 60 | `gs://<bucket>/logs/events` |

## Prerequisites

- The lakehouse deployed (`enable_lakehouse = true`) — bucket, managed folders,
  and the Iceberg REST catalog must exist.
- `gcloud` logged in with an identity that can use the BigLake catalog on the
  spoke project and write to the data bucket (a project owner/editor works).

## Run

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python seed_lakehouse.py \
  --project mini-cloud-lakehouse \
  --bucket  mini-cloud-lakehouse-data
```

Idempotent by default: a table that already has rows is left alone. Use
`--recreate` to drop and rebuild the tables.

## Consume

Point any Iceberg REST client at the catalog:

- **URI:** `https://biglake.googleapis.com/iceberg/v1/restcatalog`
- **Warehouse:** `gs://<bucket>`
- **Auth:** `Authorization: Bearer $(gcloud auth print-access-token)`
- **Header:** `x-goog-user-project: <spoke project>`
- **Header:** `X-Iceberg-Access-Delegation: vended-credentials` — required so the
  catalog vends downscoped GCS credentials; without it the client must reach the
  bucket with its own IAM, defeating the `biglake.viewer`-only consumer model.

Example (Spark):

```
spark.sql.catalog.lakehouse                 org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.lakehouse.type            rest
spark.sql.catalog.lakehouse.uri             https://biglake.googleapis.com/iceberg/v1/restcatalog
spark.sql.catalog.lakehouse.warehouse       gs://mini-cloud-lakehouse-data
spark.sql.catalog.lakehouse.header.x-goog-user-project        mini-cloud-lakehouse
spark.sql.catalog.lakehouse.header.X-Iceberg-Access-Delegation  vended-credentials
```

Then `SELECT * FROM lakehouse.sales.orders`.

## Sample read queries

### PyIceberg (Python)

```python
import subprocess
import duckdb
from pyiceberg.catalog.rest import RestCatalog
from pyiceberg.expressions import EqualTo

token = subprocess.check_output(
    ["gcloud", "auth", "print-access-token"], text=True
).strip()
cat = RestCatalog(
    "lakehouse",
    uri="https://biglake.googleapis.com/iceberg/v1/restcatalog",
    warehouse="gs://mini-cloud-lakehouse-data",
    token=token,
    **{
        "header.x-goog-user-project": "mini-cloud-lakehouse",
        "header.X-Iceberg-Access-Delegation": "vended-credentials",
    },
)

# 1. Full scan -> Arrow
orders = cat.load_table("sales.orders").scan().to_arrow()
print(orders.num_rows, "orders")

# 2. Projection + predicate pushdown (only reads matching row groups)
eu = (
    cat.load_table("sales.orders")
    .scan(row_filter=EqualTo("region", "EU-West"),
          selected_fields=("order_id", "product", "unit_price"))
    .to_arrow()
)

# 3. Aggregate with DuckDB over the Arrow table
events = cat.load_table("logs.events").scan().to_arrow()
print(duckdb.sql("""
    SELECT service, count(*) AS errors
    FROM events WHERE level = 'ERROR'
    GROUP BY service ORDER BY errors DESC
"""))
```

### Spark SQL / Trino (catalog registered as `lakehouse`)

```sql
-- sales: revenue by region
SELECT region,
       count(*)                         AS orders,
       round(sum(quantity * unit_price), 2) AS revenue
FROM lakehouse.sales.orders
GROUP BY region
ORDER BY revenue DESC;

-- logs: error/warn volume by service
SELECT service, level, count(*) AS n
FROM lakehouse.logs.events
WHERE level IN ('ERROR', 'WARN')
GROUP BY service, level
ORDER BY n DESC;

-- users: active users by country
SELECT country, count(*) AS active_users
FROM lakehouse.users.profiles
WHERE active
GROUP BY country
ORDER BY active_users DESC;
```

### BigQuery (via metastore federation — no dataset/connection)

There is no BigQuery dataset or BigLake connection, yet BigQuery can still query
these tables: the runtime catalog is a BigQuery-metastore catalog, so BigQuery
Studio discovers it and reads the Iceberg tables directly (GCS reads use the
catalog's vended credentials). Reference the table with a **4-part** name,
`` `project.catalog.namespace.table` ``:

```sql
SELECT * FROM `mini-cloud-lakehouse.mini-cloud-lakehouse-data.logs.events` LIMIT 1000;
```

A 3-part name (`mini-cloud-lakehouse-data.logs.events`) fails — BigQuery reads it as
`project.dataset.table`. Access is gated by `roles/biglake.viewer`, not by any
dataset/connection.

## Access model (feeder vs. consumer)

Access is wired in the `gcp-poc-spoke-sharedvpc` module. The design keeps the
per-folder ACLs tiny: only **feeders** and the **catalog vending SA** ever hold
direct GCS IAM; consumers borrow GCS access indirectly.

**Feeders (write).** Configured per dataset via `lakehouse_datasets[*].feeders`
in the stack. Each feeder SA gets `roles/storage.objectAdmin` on that dataset's
managed folder (`google_storage_managed_folder_iam_member.feeder`) and writes
Parquet + Iceberg metadata straight to GCS. This PoC feeds all three datasets
from the hub compute SA `311800512343-compute@developer.gserviceaccount.com`.

**Consumers (read) — no per-consumer GCS IAM.** Spark / Trino / Flink / PyIceberg
query through the Iceberg REST runtime catalog. The catalog's vending SA
(`blirc-…`) holds `roles/storage.objectUser` on each folder; in
`VENDED_CREDENTIALS` mode it mints downscoped, short-lived GCS tokens for the
engine. The caller only needs read access to the BigLake catalog — no GCS IAM and
no service-account keys.

Why it scales: managed folders cap at 1,500 principals. Routing every reader
through the catalog vending SA means adding consumers never touches folder IAM.
The full write-up lives in [docs/10-lakehouse-poc.md §3](../../../../docs/10-lakehouse-poc.md).

### Granting consumers (declarative)

Consumer grants are wired in the module — set `lakehouse_iceberg_consumers` in the
stack (no direct GCS IAM is ever added to a consumer):

```hcl
# terraform.tfvars
lakehouse_iceberg_consumers = [
  "group:analysts@example.com",
  "serviceAccount:spark@proj.iam.gserviceaccount.com",
]
```

Each member gets `roles/biglake.viewer` (project-scoped) — which includes
`biglake.tables.getData`, the permission the catalog needs to vend GCS
credentials to the engine.
