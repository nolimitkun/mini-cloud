output "project_id" {
  value = local.project_id
}

output "spoke_subnet_cidr" {
  value = google_compute_subnetwork.lakehouse.ip_cidr_range
}

output "spoke_vm_internal_ip" {
  description = "No test VM deployed — spoke subnet is ready for workloads."
  value       = null
}

# --- Lakehouse outputs ---

output "dataplex_lake_name" {
  value       = var.enable_lakehouse ? google_dataplex_lake.lakehouse[0].name : null
  description = "Dataplex Lake name."
}

output "biglake_connection_id" {
  value       = var.enable_lakehouse ? google_bigquery_connection.biglake[0].id : null
  description = "BigLake Cloud Resource connection ID (for BigLake Iceberg tables)."
}

output "bigquery_service_agent" {
  value       = var.enable_lakehouse ? google_bigquery_connection.biglake[0].cloud_resource[0].service_account_id : null
  description = "BigLake connection service account (Cloud Resource SA granted objectViewer on managed folders)."
}

output "managed_folders" {
  value = var.enable_lakehouse ? {
    for k, v in google_storage_managed_folder.dataset : k => v.name
  } : {}
  description = "Managed folders created for each dataset."
}

# --- Lakehouse Runtime Catalog outputs ---

output "iceberg_catalog_id" {
  value       = var.enable_lakehouse ? "projects/${local.project_id}/catalogs/${var.storage_bucket_name}" : null
  description = "Lakehouse Runtime Catalog ID (Iceberg REST catalog, gcloud-managed)."
}

output "iceberg_catalog_sa" {
  value       = var.enable_lakehouse ? try(data.external.iceberg_catalog_sa[0].result.biglake_service_account, null) : null
  description = "Iceberg catalog credential-vending service account."
}
