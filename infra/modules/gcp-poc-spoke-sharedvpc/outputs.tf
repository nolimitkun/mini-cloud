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

output "managed_folders" {
  value = var.enable_lakehouse ? {
    for k, v in google_storage_managed_folder.dataset : k => v.name
  } : {}
  description = "Managed folders created for each dataset."
}

# --- Lakehouse Runtime Catalog outputs ---

output "iceberg_catalog_id" {
  value       = var.enable_lakehouse ? google_biglake_iceberg_catalog.runtime[0].id : null
  description = "Lakehouse Runtime Catalog ID (Iceberg REST catalog)."
}

output "iceberg_catalog_sa" {
  value       = var.enable_lakehouse ? google_biglake_iceberg_catalog.runtime[0].biglake_service_account : null
  description = "Iceberg catalog credential-vending service account."
}
