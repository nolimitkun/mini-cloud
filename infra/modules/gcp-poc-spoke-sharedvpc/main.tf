# GCP hub-and-spoke via Shared VPC (production model; requires both projects in
# the same org). The hub project is the Shared VPC host; the spoke is a service
# project whose VM uses a subnet that lives in the HOST (hub) VPC. No peering —
# the subnet is native to the hub VPC, so the Cloud Router advertises it by
# default and on-prem reaches it directly over the tunnel.

terraform {
  required_providers {
    google   = { source = "hashicorp/google", version = "~> 5.0" }
    null     = { source = "hashicorp/null", version = "~> 3.0" }
    external = { source = "hashicorp/external", version = "~> 2.0" }
  }
}

resource "google_project" "spoke" {
  count               = var.create_project ? 1 : 0
  name                = var.spoke_project_id
  project_id          = var.spoke_project_id
  billing_account     = var.billing_account
  org_id              = var.org_id
  auto_create_network = false
  deletion_policy     = "DELETE"
}

locals {
  project_id = var.create_project ? google_project.spoke[0].project_id : var.spoke_project_id
}

# Project number (for service-account members), works whether the project is
# created here or adopted (create_project = false).
data "google_project" "spoke" {
  project_id = local.project_id
  depends_on = [google_project.spoke]
}

resource "google_project_service" "compute" {
  project            = local.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = local.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

# Enable the hub project as a Shared VPC host (needs roles/compute.xpnAdmin on the org).
resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
}

# Attach the spoke as a service project.
resource "google_compute_shared_vpc_service_project" "spoke" {
  host_project    = var.host_project_id
  service_project = local.project_id
  depends_on      = [google_compute_shared_vpc_host_project.host, google_project_service.compute]
}

# Spoke workload subnet — created in the HOST (hub) VPC.
resource "google_compute_subnetwork" "lakehouse" {
  name                     = "subnet-lakehouse"
  project                  = var.host_project_id
  region                   = var.region
  network                  = var.host_network_name
  ip_cidr_range            = var.spoke_cidr
  private_ip_google_access = true
}

# Let the service project's identities use that subnet.
resource "google_compute_subnetwork_iam_member" "compute_sa" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.lakehouse.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${data.google_project.spoke.number}-compute@developer.gserviceaccount.com"
}

resource "google_compute_subnetwork_iam_member" "cloudservices_sa" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = google_compute_subnetwork.lakehouse.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${data.google_project.spoke.number}@cloudservices.gserviceaccount.com"
}

# No test VM — spoke subnet is ready for workloads. The Shared VPC attachment,
# subnet, and IAM bindings remain so the spoke is immediately usable.

# Spoke data bucket — private, no public access, UBLA enforced. Org policy
# storage.publicAccessPrevention adds a second lock above this resource config.
resource "google_storage_bucket" "data" {
  project                     = local.project_id
  name                        = var.storage_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  depends_on                  = [google_project_service.storage]
}

# ============================================================================
# LAKEHOUSE: Dataplex Lake + Zone + Managed Folders + BigLake Connection
# ============================================================================

# Enable Dataplex API in the spoke project.
resource "google_project_service" "dataplex" {
  count              = var.enable_lakehouse ? 1 : 0
  service            = "dataplex.googleapis.com"
  project            = local.project_id
  disable_on_destroy = false
}

resource "google_project_service" "bigqueryconnection" {
  count              = var.enable_lakehouse ? 1 : 0
  project            = local.project_id
  service            = "bigqueryconnection.googleapis.com"
  disable_on_destroy = false
}

# BigQuery core API — required for the lakehouse dataset resource.
resource "google_project_service" "bigquery" {
  count              = var.enable_lakehouse ? 1 : 0
  project            = local.project_id
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

# BigLake API — required for the Iceberg REST catalog (created via gcloud).
resource "google_project_service" "biglake" {
  count              = var.enable_lakehouse ? 1 : 0
  project            = local.project_id
  service            = "biglake.googleapis.com"
  disable_on_destroy = false
}

# Dataplex Lake — top-level logical container.
resource "google_dataplex_lake" "lakehouse" {
  count        = var.enable_lakehouse ? 1 : 0
  name         = "lakehouse"
  location     = var.region
  project      = local.project_id
  description  = "Lakehouse data lake for mini-cloud PoC"
  display_name = "Mini-Cloud Lakehouse"
  depends_on   = [google_project_service.dataplex]
}

# Dataplex Zone — single zone for PoC (RAW, where data lands).
# Add a CURATED zone later when transformation pipelines are built.
resource "google_dataplex_zone" "raw" {
  count        = var.enable_lakehouse ? 1 : 0
  name         = "raw"
  location     = var.region
  lake         = google_dataplex_lake.lakehouse[0].name
  project      = local.project_id
  type         = "RAW"
  description  = "Raw ingested data zone"
  display_name = "Raw Zone"

  discovery_spec {
    enabled = true
    csv_options {
      delimiter              = ","
      header_rows            = 1
      disable_type_inference = false
    }
    json_options {
      disable_type_inference = false
    }
  }

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  # json_options block tends to drift; suppress the perpetual diff.
  lifecycle {
    ignore_changes = [discovery_spec[0].json_options]
  }

  depends_on = [google_dataplex_lake.lakehouse]
}

# Managed folders: one per dataset. Each gets its own IAM policy.
resource "google_storage_managed_folder" "dataset" {
  for_each      = var.enable_lakehouse ? var.datasets : {}
  bucket        = google_storage_bucket.data.name
  name          = "${each.key}/"
  force_destroy = true
}

# Feeder IAM — objectAdmin (read + write + delete) on each dataset folder.
resource "google_storage_managed_folder_iam_member" "feeder" {
  for_each = var.enable_lakehouse ? merge([
    for ds, cfg in var.datasets : {
      for feeder in cfg.feeders : "${ds}/${feeder}" => {
        dataset = ds
        feeder  = feeder
      }
    }
  ]...) : {}

  bucket         = google_storage_bucket.data.name
  managed_folder = google_storage_managed_folder.dataset[each.value.dataset].name
  role           = "roles/storage.objectAdmin"
  member         = "serviceAccount:${each.value.feeder}"
}

# BigLake connection — Cloud Resource type for BigLake Iceberg managed tables.
# Creates an internal SA: bqcx-{project_number}-{id}@gcp-sa-bigquery-condel...
resource "google_bigquery_connection" "biglake" {
  count         = var.enable_lakehouse ? 1 : 0
  connection_id = "biglake-gcs"
  location      = var.region
  project       = local.project_id
  friendly_name = "BigLake GCS connection"
  description   = "Cloud Resource connection for BigLake Iceberg managed tables on GCS"
  cloud_resource {}
  depends_on = [google_project_service.bigqueryconnection]
}

# Grant the BigLake connection's service agent objectUser (read + write + delete)
# on each managed folder so BigLake can create/write/delete objects for managed
# Iceberg tables via the connection. objectViewer is read-only and cannot back
# CREATE TABLE ... OPTIONS(table_format='ICEBERG') or loads into managed tables.
resource "google_storage_managed_folder_iam_member" "biglake_writer" {
  for_each = var.enable_lakehouse ? var.datasets : {}

  bucket         = google_storage_bucket.data.name
  managed_folder = google_storage_managed_folder.dataset[each.key].name
  role           = "roles/storage.objectUser"
  member         = "serviceAccount:${google_bigquery_connection.biglake[0].cloud_resource[0].service_account_id}"
}

# BigQuery also requires bucket metadata access on the connection SA for managed
# Iceberg tables; legacyBucketReader is a bucket-level role, so grant it there.
resource "google_storage_bucket_iam_member" "biglake_bucket_reader" {
  count  = var.enable_lakehouse ? 1 : 0
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_bigquery_connection.biglake[0].cloud_resource[0].service_account_id}"
}

# BigQuery dataset for lakehouse catalog — where BigLake Iceberg tables live.
resource "google_bigquery_dataset" "lakehouse" {
  count       = var.enable_lakehouse ? 1 : 0
  dataset_id  = var.bigquery_dataset_id
  location    = var.region
  project     = local.project_id
  description = "Lakehouse catalog — BigLake Iceberg managed tables"
  depends_on  = [google_project_service.bigquery]
}

# ============================================================================
# LAKEHOUSE RUNTIME CATALOG — Iceberg REST Catalog for open-source engines
# ============================================================================

# BigLake Iceberg Catalog — serves the Iceberg REST API endpoint that
# Spark, Trino, Flink, and other open-source engines use to discover and
# query Iceberg tables. This is the "Lakehouse Runtime Catalog".
#
# CATALOG_TYPE_GCS_BUCKET: the catalog name must match the GCS bucket name.
# The catalog maps 1:1 to our existing data bucket.
#
# CREDENTIAL_MODE_VENDED_CREDENTIALS: the catalog generates downscoped GCS
# tokens for query engines, so they don't need their own GCS SA keys.
#
# NOTE: The google_biglake_iceberg_catalog Terraform resource requires
# provider >= v7.x. We use gcloud via null_resource until we upgrade.
# Once upgraded, replace this block with the native resource.
resource "null_resource" "iceberg_catalog" {
  count = var.enable_lakehouse ? 1 : 0
  triggers = {
    bucket  = google_storage_bucket.data.name
    project = local.project_id
  }
  provisioner "local-exec" {
    command     = <<-EOT
      gcloud alpha biglake iceberg catalogs describe ${google_storage_bucket.data.name} \
        --project=${local.project_id} 2>/dev/null && echo "EXISTS" || \
      gcloud alpha biglake iceberg catalogs create ${google_storage_bucket.data.name} \
        --catalog-type=gcs-bucket \
        --credential-mode=vended-credentials \
        --project=${local.project_id}
    EOT
    interpreter = ["bash", "-c"]
  }
  # destroy provisioner: can only reference self.triggers, so the project is
  # captured in triggers above and used here to target the actual spoke project.
  provisioner "local-exec" {
    when        = destroy
    command     = "gcloud alpha biglake iceberg catalogs delete ${self.triggers.bucket} --project=${self.triggers.project} --quiet || true"
    interpreter = ["bash", "-c"]
  }
  depends_on = [google_project_service.biglake]
}

# Fetch the catalog's credential-vending service account.
# This SA is auto-created when the catalog is provisioned.
data "external" "iceberg_catalog_sa" {
  count = var.enable_lakehouse ? 1 : 0
  program = ["bash", "-c", <<-EOT
    SA=$(gcloud alpha biglake iceberg catalogs describe ${google_storage_bucket.data.name} \
      --project=${local.project_id} --format='value(biglake-service-account)' 2>/dev/null || echo "")
    jq -n --arg sa "$SA" '{"biglake_service_account":$sa}'
  EOT
  ]
  depends_on = [null_resource.iceberg_catalog]
}

# Grant the Iceberg catalog's credential-vending SA objectUser on each managed
# folder. The runtime catalog needs write access to create namespaces/tables and
# write Iceberg metadata; the downscoped credentials it vends to Spark/Trino are
# bounded by this grant, so objectViewer would leave those jobs read-only.
#
# Note: the SA is computed at apply time (via data.external). The for_each
# iterates var.datasets unconditionally; on first apply the null_resource
# must be targeted separately to create the catalog before this resource
# can resolve the member attribute.
resource "google_storage_managed_folder_iam_member" "iceberg_catalog_writer" {
  for_each       = var.enable_lakehouse ? var.datasets : {}
  bucket         = google_storage_bucket.data.name
  managed_folder = google_storage_managed_folder.dataset[each.key].name
  role           = "roles/storage.objectUser"
  member         = "serviceAccount:${try(data.external.iceberg_catalog_sa[0].result.biglake_service_account, "")}"
}
