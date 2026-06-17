output "host_project_id" {
  description = "Shared VPC host project id."
  value       = google_compute_network.hub.project
}

output "network_self_link" {
  description = "Hub VPC self link for service-project subnets."
  value       = google_compute_network.hub.self_link
}

output "router_name" {
  value = google_compute_router.hub.name
}
