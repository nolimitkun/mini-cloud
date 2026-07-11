# GCP hub-and-spoke via Shared VPC (production model; requires both projects in
# the same org). The hub project is the Shared VPC host; the spoke is a service
# project whose VM uses a subnet that lives in the HOST (hub) VPC. No peering —
# the subnet is native to the hub VPC, so the Cloud Router advertises it by
# default and on-prem reaches it directly over the tunnel.

terraform {
  required_providers {
    # >= 7.15 for google_biglake_iceberg_catalog (native Iceberg REST catalog,
    # added in v7.15.0).
    google = { source = "hashicorp/google", version = ">= 7.15.0, < 8.0" }
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
# LAKEHOUSE: Managed Folders + Iceberg Runtime Catalog (open engines only)
# ============================================================================

# BigLake API — required for the Iceberg REST catalog.
resource "google_project_service" "biglake" {
  count              = var.enable_lakehouse ? 1 : 0
  project            = local.project_id
  service            = "biglake.googleapis.com"
  disable_on_destroy = false
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
resource "google_biglake_iceberg_catalog" "runtime" {
  count           = var.enable_lakehouse ? 1 : 0
  project         = local.project_id
  name            = google_storage_bucket.data.name
  catalog_type    = "CATALOG_TYPE_GCS_BUCKET"
  credential_mode = "CREDENTIAL_MODE_VENDED_CREDENTIALS"
  depends_on      = [google_project_service.biglake]
}

# Grant the Iceberg catalog's credential-vending SA objectUser on each managed
# folder. The runtime catalog needs write access to create namespaces/tables and
# write Iceberg metadata; the downscoped credentials it vends to Spark/Trino are
# bounded by this grant, so objectViewer would leave those jobs read-only.
resource "google_storage_managed_folder_iam_member" "iceberg_catalog_writer" {
  for_each       = var.enable_lakehouse ? var.datasets : {}
  bucket         = google_storage_bucket.data.name
  managed_folder = google_storage_managed_folder.dataset[each.key].name
  role           = "roles/storage.objectUser"
  member         = "serviceAccount:${google_biglake_iceberg_catalog.runtime[0].biglake_service_account}"
}

# ============================================================================
# CONSUMER ACCESS (read) — declarative grants, no direct GCS IAM
# ============================================================================

# Open-engine consumers (Spark/Trino/PyIceberg): read via the Iceberg REST
# catalog. biglake.viewer includes biglake.tables.getData — the permission that
# lets the catalog vend downscoped GCS credentials to the engine. BigLake
# catalogs are project-scoped, so the grant is project-level.
resource "google_project_iam_member" "iceberg_consumer" {
  for_each = var.enable_lakehouse ? toset(var.iceberg_consumers) : []
  project  = local.project_id
  role     = "roles/biglake.viewer"
  member   = each.value
}
