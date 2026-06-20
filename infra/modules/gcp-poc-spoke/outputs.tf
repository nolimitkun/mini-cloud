output "project_id" {
  value = local.project_id
}

output "spoke_subnet_cidr" {
  value = google_compute_subnetwork.spoke.ip_cidr_range
}

output "spoke_vm_internal_ip" {
  description = "Private IP of the spoke test VM (reachable from on-prem over the tunnel)."
  value       = google_compute_instance.spoke_test.network_interface[0].network_ip
}
