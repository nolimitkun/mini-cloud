# GCP hub-and-spoke (PoC): a separate spoke project + VPC, peered to the hub VPC.
# Standalone projects (no org) => VPC peering, not Shared VPC. The spoke's subnet
# is reachable from on-prem because the hub Cloud Router advertises it (see the
# advertised_extra_ranges var on the gcp-vpn-poc module); on-prem routes reach the
# spoke via the peering (custom-route import/export).

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = ">= 5.0, < 8.0" }
  }
}

resource "google_project" "spoke" {
  count               = var.create_project ? 1 : 0
  name                = var.spoke_project_id
  project_id          = var.spoke_project_id
  billing_account     = var.billing_account
  org_id              = var.org_id != "" ? var.org_id : null
  auto_create_network = false # no default network
  deletion_policy     = "DELETE"
}

locals {
  project_id = var.create_project ? google_project.spoke[0].project_id : var.spoke_project_id
}

resource "google_project_service" "compute" {
  project            = local.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "spoke" {
  project                 = local.project_id
  name                    = "vpc-lakehouse"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "spoke" {
  project                  = local.project_id
  name                     = "subnet-lakehouse"
  region                   = var.region
  network                  = google_compute_network.spoke.id
  ip_cidr_range            = var.spoke_cidr
  private_ip_google_access = true
}

# --- VPC peering hub <-> spoke (custom routes so on-prem/VPN routes propagate) ---
resource "google_compute_network_peering" "spoke_to_hub" {
  name                 = "lakehouse-to-hub"
  network              = google_compute_network.spoke.self_link
  peer_network         = var.hub_network
  import_custom_routes = true
  export_custom_routes = true
}

resource "google_compute_network_peering" "hub_to_spoke" {
  name                 = "hub-to-lakehouse"
  network              = var.hub_network
  peer_network         = google_compute_network.spoke.self_link
  import_custom_routes = true
  export_custom_routes = true
}

# --- Spoke firewall: on-prem LAN + IAP only; no public exposure ---
resource "google_compute_firewall" "from_onprem" {
  project       = local.project_id
  name          = "allow-from-onprem"
  network       = google_compute_network.spoke.id
  direction     = "INGRESS"
  source_ranges = [var.onprem_lan_cidr]
  allow { protocol = "icmp" }
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = local.project_id
  name          = "allow-iap-ssh"
  network       = google_compute_network.spoke.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# --- Spoke test VM, no external IP ---
resource "google_compute_instance" "spoke_test" {
  project      = local.project_id
  name         = "lakehouse-test-vm"
  zone         = var.zone
  machine_type = "e2-micro"
  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.spoke.id
    # no access_config => no external IP
  }
}
