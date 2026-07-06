# Lakehouse — GCS Data Lake + Knowledge Catalog + Runtime Catalog (PoC)

**Status:** PoC v0.1 — deployed in `mini-cloud-lakehouse`
**Branch:** `feat/lakehouse-poc`
**Purpose:** Extend the GCP VPN PoC with a full lakehouse stack: GCS storage, Knowledge Catalog
(Dataplex), Lakehouse Runtime Catalog (Iceberg REST), and BigLake for BigQuery access.

> This builds on the shared-VPC spoke from [08-poc-vpn.md](08-poc-vpn.md). The spoke project
> `mini-cloud-lakehouse` was an empty GCS bucket; it now has three catalog layers and managed
> folder IAM controlling cross-project feeder/consumer access.

---

## 1. Architecture

![Lakehouse architecture: GCS + Knowledge Catalog + Runtime Catalog + BigLake](diagrams/gcp-lakehouse-architecture.html)

```
                          Knowledge Catalog
                          (Dataplex Lake+Zone)
                          governance · discovery · lineage
                                   ▲
                                   │ auto-discovery
┌──────────────┐     write    ┌────┴────────────────────────────┐
│ Feeder Proj  │─────────────▶│  GCS Storage Layer              │
│ (hub)        │ objectAdmin  │  mini-cloud-lakehouse-data      │
│              │              │  ├── sales/   (managed folder)  │
└──────────────┘              │  ├── users/   (managed folder)  │
                              │  └── logs/    (managed folder)  │
                              │  Iceberg table format (Parquet)  │
                              └────┬────────────────────────────┘
                                   │ Iceberg metadata sync
                                   ▼
                          Lakehouse Runtime Catalog
                          (Iceberg REST Catalog)
                          table snapshots · manifests · schema
                          credential mode: VENDED_CREDENTIALS
                           │                    │
                    Iceberg REST API    vended GCS token
                           │                    │
                    ┌──────▼──────┐    ┌───────▼──────────┐
                    │ Consumer B  │    │ BigLake Conn.     │
                    │ Spark/Trino │    │ (Cloud Resource)  │
                    │ open engine │    │ ───────────────── │
                    └─────────────┘    │ Consumer A        │
                                       │ BigQuery / Looker │
                                       └───────────────────┘
```

### Three catalog layers

| Layer | Resource | Role | In query path? |
|---|---|---|---|
| **Knowledge Catalog** | `google_dataplex_lake` + `zone` | Governance: discovery, lineage, glossary, quality | No — out of band |
| **Lakehouse Runtime Catalog** | BigLake Iceberg Catalog (`gcloud alpha` / `null_resource`) | Operational: serves Iceberg REST API to Spark/Trino, vends GCS credentials | **Yes** — hot path |
| **BigLake Connection** | `google_bigquery_connection` (Cloud Resource) | Bridge: BigQuery → GCS reads via delegated SA | **Yes** — hot path |

Key distinction: **Knowledge Catalog** helps humans find data. **Runtime Catalog** helps query engines read it.

---

## 2. Terraform resources (20 total)

All live in the `gcp-poc-spoke-sharedvpc` module, toggled by `enable_lakehouse = true`.

### APIs

| Resource | API |
|---|---|
| `google_project_service.dataplex` | `dataplex.googleapis.com` |
| `google_project_service.bigqueryconnection` | `bigqueryconnection.googleapis.com` |

### Catalog

| Resource | Detail |
|---|---|
| `google_dataplex_lake.lakehouse` | Name: `lakehouse`, location: `europe-west1` |
| `google_dataplex_zone.raw` | Zone: `raw`, type: RAW, CSV/JSON auto-discovery |
| `null_resource.iceberg_catalog` | Iceberg REST catalog via `gcloud alpha biglake iceberg catalogs create` |
| `data.external.iceberg_catalog_sa` | Reads catalog's credential-vending SA at apply time |

### Storage

| Resource | Detail |
|---|---|
| `google_storage_bucket.data` | `mini-cloud-lakehouse-data`, UBLA enforced, public access prevented |
| `google_storage_managed_folder.dataset` (×3) | `sales/`, `users/`, `logs/` |

### BigLake + BigQuery

| Resource | Detail |
|---|---|
| `google_bigquery_connection.biglake` | Connection ID: `biglake-gcs`, Cloud Resource type |
| `google_bigquery_dataset.lakehouse` | Dataset: `lakehouse_catalog` |

### IAM bindings (9 total)

| SA | Role | Folders | Purpose |
|---|---|---|---|
| `311800512343-compute@developer` (hub feeder) | `storage.objectAdmin` | all 3 | Direct write to GCS |
| `bqcx-367509735644-3m7e@gcp-sa-bigquery-condel` | `storage.objectViewer` | all 3 | BigLake delegated read for BigQuery consumers |
| `blirc-367509735644-7den@gcp-sa-biglakerestcatalog` | `storage.objectViewer` | all 3 | Vended credentials for Spark/Trino via Iceberg catalog |

---

## 3. Access model

### Feeder (write)

The hub project `mini-cloud-499820` writes directly to GCS via its compute SA.
Granted `storage.objectAdmin` on each managed folder. Spark/Flink jobs write
Parquet data files and commit Iceberg table metadata to the `metadata/` prefix
within each folder.

### BigQuery consumer (read)

Consumer A (Analytics team) queries via BigLake managed Iceberg tables:

```sql
CREATE OR REPLACE EXTERNAL TABLE `mini-cloud-lakehouse.lakehouse_catalog.sales`
WITH CONNECTION `mini-cloud-lakehouse.europe-west1.biglake-gcs`
OPTIONS (format = 'ICEBERG', uris = ['gs://mini-cloud-lakehouse-data/sales/']);
```

The BigLake Connection SA (`bqcx-...`) holds `objectViewer` on GCS. The consumer
only needs `bigquery.connections.use` — **no GCS IAM needed per consumer**.

### Open-source engine consumer (read)

Consumer B (Spark, Trino, Python) queries via the Iceberg REST Catalog:

```java
// Spark config
spark.sql.catalog.lakehouse = org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.lakehouse.catalog-impl = org.apache.iceberg.rest.RESTCatalog
spark.sql.catalog.lakehouse.uri = https://biglake.googleapis.com/iceberg/v1/restcatalog/extensions/projects/mini-cloud-lakehouse/catalogs/mini-cloud-lakehouse-data
spark.sql.catalog.lakehouse.credential = vended-credentials
```

The catalog SA (`blirc-...`) vends downscoped GCS tokens. The engine does not
need its own GCS service account key.

---

## 4. Iceberg catalog (gcloud-managed)

The `google_biglake_iceberg_catalog` Terraform resource requires provider ≥ v7.x.
We use `null_resource` + `gcloud alpha` as a bridge until the provider is upgraded.

```bash
# Create (idempotent via Terraform null_resource)
gcloud alpha biglake iceberg catalogs create mini-cloud-lakehouse-data \
  --catalog-type=gcs-bucket \
  --credential-mode=vended-credentials \
  --project=mini-cloud-lakehouse

# Inspect
gcloud alpha biglake iceberg catalogs describe mini-cloud-lakehouse-data \
  --project=mini-cloud-lakehouse --format=json
```

When upgrading to `hashicorp/google ~> 7.0`, replace with the native resource:

```hcl
resource "google_biglake_iceberg_catalog" "runtime" {
  name            = google_storage_bucket.data.name
  catalog_type    = "CATALOG_TYPE_GCS_BUCKET"
  credential_mode = "CREDENTIAL_MODE_VENDED_CREDENTIALS"
  project         = local.project_id
}
```

---

## 5. Deploy order

1. `terraform apply -target='module.spoke_shared[0].null_resource.iceberg_catalog[0]'`
   — creates the Iceberg REST catalog first (needed before IAM bindings can resolve the SA)
2. `terraform apply` — creates remaining resources (zone, IAM, BQ dataset)

The catalog's credential-vending SA is only known after creation; the `data.external`
resource reads it at apply time so the IAM bindings reference the correct principal.

---

## 6. Limits & considerations

- **IAM principal ceiling**: 1,500 principals per managed folder. Mitigated by using
  BigLake Connection SA (1 SA bridges all BigQuery consumers) and Iceberg catalog
  vended credentials (no per-consumer GCS IAM needed for open-source engines).
- **Provider version**: Iceberg catalog uses gcloud; migrate to native resource after
  upgrading to `hashicorp/google ~> 7.0`.
- **IAM propagation**: Changes take up to 7 minutes to propagate globally.
- **Managed folder nesting**: Up to 15 levels. Current datasets are flat (`sales/`,
  `users/`, `logs/`) with Iceberg metadata under `{dataset}/metadata/`.
- **Cross-project IAM**: Uses standard `serviceAccount:EMAIL` syntax. Feeder SAs
  from the hub project are grantable as long as the calling identity has
  `iam.serviceAccounts.get` on that project (org-level permissions cover this).

---

## 7. Related docs

- [08 — PoC VPN (GCP)](08-poc-vpn.md) — the base PoC this builds on
- [01 — Architecture specification](01-architecture-specification.md) — design goals and decisions
- [04 — Security baseline](04-security-baseline.md) — org policy guardrails
- [Architecture diagram (HTML)](diagrams/gcp-lakehouse-architecture.html) — interactive SVG diagram
