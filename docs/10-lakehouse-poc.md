# Lakehouse — GCS Data Lake + Runtime Catalog (PoC)

**Status:** PoC — deployed in `mini-cloud-lakehouse`, merged to `main` (PR #8)
**Purpose:** Extend the GCP VPN PoC with a lakehouse stack: GCS storage and the Lakehouse
Runtime Catalog (Iceberg REST) for open-engine (Spark/Trino/Flink/PyIceberg) access.

> This builds on the shared-VPC spoke from [08-poc-vpn.md](08-poc-vpn.md). The spoke project
> `mini-cloud-lakehouse` was an empty GCS bucket; it now has the Iceberg runtime catalog plus
> managed folder IAM controlling cross-project feeder/consumer access.
>
> **Scope note:** an earlier draft included a Knowledge Catalog layer (Dataplex Lake + Zone) for
> governance/discovery. It was dropped from the PoC — it sits out of band from the query path and
> is not required for the lakehouse to function. See [§7](#7-when-a-knowledge-catalog-is-worth-adding)
> for when to add it back.

---

## 1. Architecture

![Lakehouse architecture: GCS + Iceberg Runtime Catalog](diagrams/gcp-lakehouse-architecture.html)

```
┌──────────────┐     write    ┌─────────────────────────────────┐
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
                          (BigLake Iceberg REST Catalog)
                          table snapshots · manifests · schema
                          credential mode: VENDED_CREDENTIALS
                           │                    │
                    Iceberg REST API    vended GCS token
                           │                    │
                          ┌▼────────────────────▼┐
                          │ Consumer: Open Engine │
                          │ Spark/Trino/Flink/Py  │
                          │ roles/biglake.viewer  │
                          └───────────────────────┘
```

### One catalog layer

| Layer | Resource | Role | In query path? |
|---|---|---|---|
| **Lakehouse Runtime Catalog** | `google_biglake_iceberg_catalog` (native, provider ≥ 7.15) | Operational: serves Iceberg REST API to Spark/Trino/Flink/PyIceberg, vends GCS credentials | **Yes** — hot path |

The runtime catalog is the only catalog: it lets open-source engines discover and read Iceberg
tables directly. We removed the earlier BigLake connection + `lakehouse_catalog` dataset — but note
those were a *redundant* BigQuery path, not the only one (see [§3.1](#31-bigquery-sees-it-anyway-metastore-federation)):
BigQuery can still query these tables through the BigLake metastore integration, because the runtime
catalog **is** a BigQuery-metastore catalog. A governance/discovery layer (Knowledge Catalog) is
out of scope — see [§7](#7-when-a-knowledge-catalog-is-worth-adding).

---

## 2. Terraform resources (12 lakehouse resources)

All live in the `gcp-poc-spoke-sharedvpc` module, toggled by `enable_lakehouse = true`.

### APIs

| Resource | API |
|---|---|
| `google_project_service.biglake` | `biglake.googleapis.com` |

### Runtime Catalog

| Resource | Detail |
|---|---|
| `google_biglake_iceberg_catalog.runtime` | Iceberg REST catalog, `gcs-bucket` type, vended credentials; exports the credential-vending SA (`biglake_service_account`) at plan/apply time |

### Storage

| Resource | Detail |
|---|---|
| `google_storage_bucket.data` | `mini-cloud-lakehouse-data`, UBLA enforced, public access prevented |
| `google_storage_managed_folder.dataset` (×3) | `sales/`, `users/`, `logs/` |

### IAM bindings (6 folder bindings + optional consumers)

| Principal | Role | Folders | Purpose |
|---|---|---|---|
| `311800512343-compute@developer` (hub feeder) | `storage.objectAdmin` | all 3 | Direct write to GCS |
| `blirc-367509735644-7den@gcp-sa-biglakerestcatalog` | `storage.objectUser` | all 3 | Vended credentials for Spark/Trino via Iceberg catalog |
| `lakehouse_iceberg_consumers[*]` | `roles/biglake.viewer` | project | Read via Iceberg REST — no GCS IAM (empty by default) |

---

## 3. Access model

### Feeder (write)

The hub project `mini-cloud-499820` writes directly to GCS via its compute SA.
Granted `storage.objectAdmin` on each managed folder. Spark/Flink jobs write
Parquet data files and commit Iceberg table metadata to the `metadata/` prefix
within each folder.

### Open-source engine consumer (read)

Consumers (Spark, Trino, Flink, Python) query via the Iceberg REST Catalog:

```java
// Spark config
spark.sql.catalog.lakehouse = org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.lakehouse.catalog-impl = org.apache.iceberg.rest.RESTCatalog
spark.sql.catalog.lakehouse.uri = https://biglake.googleapis.com/iceberg/v1/restcatalog/extensions/projects/mini-cloud-lakehouse/catalogs/mini-cloud-lakehouse-data
spark.sql.catalog.lakehouse.credential = vended-credentials
```

The catalog SA (`blirc-...`) vends downscoped GCS tokens. The engine does not
need its own GCS service account key.

### 3.1 BigQuery sees it anyway (metastore federation)

The runtime catalog is created as a **BigQuery-metastore** catalog
(`catalog_type = "CATALOG_TYPE_GCS_BUCKET"`), so the
tables show up in BigQuery Studio under the catalog `mini-cloud-lakehouse-data`
(→ namespaces `sales`/`users`/`logs` → tables) and BigQuery can query them
directly — **without** a BigQuery dataset or a BigLake connection. GCS reads use
the catalog's vended credentials (the `blirc-…` SA), not a per-user grant.

So the `lakehouse_catalog` dataset + BigLake connection we removed were a *second,
redundant* BigQuery path (classic BigLake external tables). Removing them did not
take BigQuery access away — the metastore-native path still works. This is a
platform behaviour of the catalog itself, not something the module provisions.

Access is gated by BigLake catalog IAM: an identity needs `roles/biglake.viewer`
(includes `biglake.tables.getData`) to read via the metastore, which is exactly
the `lakehouse_iceberg_consumers` grant. Project Owners/Editors can always query.
There is no way to keep the runtime catalog while hiding it from BigQuery — the two
are the same catalog.

**Query syntax.** Reference the table with a **4-part** name,
`` `project.catalog.namespace.table` `` — the catalog sits between project and
namespace:

```sql
SELECT * FROM `mini-cloud-lakehouse.mini-cloud-lakehouse-data.logs.events` LIMIT 1000;
```

The common mistake is a 3-part name (`mini-cloud-lakehouse-data.logs.events`),
which BigQuery parses as `project.dataset.table` and rejects (`Dataset not found`).
Here `mini-cloud-lakehouse` is the project, `mini-cloud-lakehouse-data` is the
catalog (same as the bucket), `logs` the namespace, `events` the table.

---

## 4. Iceberg catalog (native Terraform resource)

The catalog is the native `google_biglake_iceberg_catalog` resource (provider ≥ 7.15):

```hcl
resource "google_biglake_iceberg_catalog" "runtime" {
  project         = local.project_id
  name            = google_storage_bucket.data.name # gcs-bucket type: name must match the bucket
  catalog_type    = "CATALOG_TYPE_GCS_BUCKET"
  credential_mode = "CREDENTIAL_MODE_VENDED_CREDENTIALS"
}
```

It exports `biglake_service_account` — the credential-vending SA (`blirc-…`) — so the managed-folder
IAM bindings reference it directly; no `gcloud` or apply-time lookup needed.

An earlier revision bridged this with `null_resource` + `gcloud alpha biglake iceberg catalogs create`
while the stack was on provider 5.x. To inspect the live catalog:

```bash
gcloud alpha biglake iceberg catalogs describe mini-cloud-lakehouse-data \
  --project=mini-cloud-lakehouse --format=json
```

---

## 5. Deploy order

A single `terraform apply` — the catalog's vending SA is a plan-time attribute of the native
resource, so the IAM bindings resolve without the old two-step targeted apply.

### Migrating a deployment created with the gcloud bridge

If the state still holds `null_resource.iceberg_catalog` (pre-provider-7 revision), **do not just
apply**: removing the `null_resource` from config triggers its destroy provisioner, which deletes
the live catalog. Instead:

```bash
cd infra/stacks/gcp-poc
terraform state rm 'module.spoke_shared[0].null_resource.iceberg_catalog[0]'
terraform state rm 'module.spoke_shared[0].data.external.iceberg_catalog_sa[0]'
terraform import 'module.spoke_shared[0].google_biglake_iceberg_catalog.runtime[0]' \
  mini-cloud-lakehouse/mini-cloud-lakehouse-data
terraform plan   # expect: no create/destroy of the catalog; IAM bindings unchanged
```

---

## 6. Limits & considerations

- **IAM principal ceiling**: 1,500 principals per managed folder. Mitigated by the
  Iceberg catalog's vended credentials — consumers get `roles/biglake.viewer` and the
  catalog vends GCS access, so no per-consumer GCS IAM is ever added to a folder.
- **Provider version**: the gcp-poc stack pins `hashicorp/google ~> 7.0` for the native
  `google_biglake_iceberg_catalog` resource; the other GCP stacks still run 5.x.
- **IAM propagation**: Changes take up to 7 minutes to propagate globally.
- **Managed folder nesting**: Up to 15 levels. Current datasets are flat (`sales/`,
  `users/`, `logs/`) with Iceberg metadata under `{dataset}/metadata/`.
- **Cross-project IAM**: Uses standard `serviceAccount:EMAIL` syntax. Feeder SAs
  from the hub project are grantable as long as the calling identity has
  `iam.serviceAccounts.get` on that project (org-level permissions cover this).

---

## 7. When a Knowledge Catalog is worth adding

The PoC ships without a Knowledge Catalog (Dataplex Lake + Zone). The Runtime Catalog is the
hard requirement — Iceberg cannot function without a catalog to map table names to metadata
snapshots and serialize commits — but a Knowledge Catalog is a governance/discovery overlay that
sits **out of band from the query path**. No query fails without it, so for a single-team PoC over
a handful of known tables it adds operational surface with little payoff.

It becomes worth adding when:

- **Multiple teams** produce and consume data and can no longer find tables by tribal knowledge
  (roughly a few dozen tables in).
- **Compliance / PII** obligations require tagging, policy propagation, and lineage to answer
  "where does this data flow?"
- **Data-quality SLAs** need Dataplex auto-DQ and profiling to attach to a catalog layer.

Two GCP specifics worth knowing:

- BigQuery datasets and BigLake tables are **already indexed** in Dataplex Universal Catalog search
  without any Lake/Zone resources, so basic discovery exists even now. An explicit Lake/Zone adds
  GCS-level auto-discovery (crawling raw CSV/JSON), zone governance, and managed quality/profiling.
- Google is converging these layers: the BigLake metastore is increasingly the single metastore
  whose entries surface in Dataplex automatically, so registering in the runtime catalog
  increasingly yields knowledge-catalog visibility as a side effect.

To add it back, re-introduce `google_dataplex_lake` + `google_dataplex_zone` (and the
`dataplex.googleapis.com` service) in the `gcp-poc-spoke-sharedvpc` module.

---

## 8. Related docs

- [08 — PoC VPN (GCP)](08-poc-vpn.md) — the base PoC this builds on
- [01 — Architecture specification](01-architecture-specification.md) — design goals and decisions
- [04 — Security baseline](04-security-baseline.md) — org policy guardrails
- [Architecture diagram (HTML)](diagrams/gcp-lakehouse-architecture.html) — interactive SVG diagram
