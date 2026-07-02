# GCP workload spoke: a service project attached to the Shared VPC host (hub),
# with its own subnet in the host network. No external IPs (org policy enforced);
# egress/east-west traverse the hub firewall. Spokes do not route to each other.

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

# Attach the workload (service) project to the Shared VPC host.
resource "google_compute_shared_vpc_service_project" "spoke" {
  host_project    = var.host_project_id
  service_project = var.service_project_id
}

# Spoke subnet (private plane) lives in the host (hub) network — Shared VPC model.
resource "google_compute_subnetwork" "spoke" {
  name                     = "subnet-${var.name}"
  project                  = var.host_project_id
  region                   = var.region
  network                  = var.host_network_name
  ip_cidr_range            = var.spoke_cidr
  private_ip_google_access = true
}

# Cross-cloud subnet (172.x plane): only resources approved for spoke-to-spoke flows (doc 02 §1.2).
resource "google_compute_subnetwork" "crosscloud" {
  name                     = "subnet-${var.name}-xcloud"
  project                  = var.host_project_id
  region                   = var.region
  network                  = var.host_network_name
  ip_cidr_range            = var.crosscloud_cidr
  private_ip_google_access = true
}
