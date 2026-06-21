output "spoke_subnet_name" {
  description = "Spoke private-plane subnet name (lives in the host VPC)."
  value       = google_compute_subnetwork.spoke.name
}

output "spoke_subnet_id" {
  description = "Spoke private-plane subnet ID."
  value       = google_compute_subnetwork.spoke.id
}

output "crosscloud_subnet_name" {
  description = "Spoke cross-cloud subnet name (lives in the host VPC)."
  value       = google_compute_subnetwork.crosscloud.name
}

output "crosscloud_subnet_id" {
  description = "Spoke cross-cloud subnet ID."
  value       = google_compute_subnetwork.crosscloud.id
}
