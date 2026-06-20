# GCP hub-and-spoke via Shared VPC (production model; requires both projects in
# the same org). The hub project is the Shared VPC host; the spoke is a service
# project whose VM uses a subnet that lives in the HOST (hub) VPC. No peering —
# the subnet is native to the hub VPC, so the Cloud Router advertises it by
# default and on-prem reaches it directly over the tunnel.

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
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

# Spoke test VM (in the service project) using the host subnet; no external IP.
resource "google_compute_instance" "spoke_test" {
  project      = local.project_id
  name         = "lakehouse-test-vm"
  zone         = var.zone
  machine_type = "e2-micro"
  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork         = google_compute_subnetwork.lakehouse.self_link
    subnetwork_project = var.host_project_id
  }
  depends_on = [google_compute_shared_vpc_service_project.spoke]
}
