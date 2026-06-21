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
