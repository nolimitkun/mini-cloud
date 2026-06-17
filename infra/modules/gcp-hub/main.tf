# GCP Tier-2 cloud hub: Cloud Interconnect + Cloud Router (HA), Shared VPC host,
# Cloud DNS forwarding, firewall. Private-only: no external IPs (org policy enforced).

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

# Shared VPC host network = the Tier-2 hub.
resource "google_compute_network" "hub" {
  name                    = "vpc-hub"
  project                 = var.project_id
  auto_create_subnetworks = false # no default network (org policy also enforces this)
}

resource "google_compute_subnetwork" "hub" {
  name                     = "subnet-hub"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.hub.id
  ip_cidr_range            = var.hub_cidr
  private_ip_google_access = true # Private Google Access — no public path to Google APIs
}

# Enable this project as a Shared VPC host (spokes attach as service projects).
resource "google_compute_shared_vpc_host_project" "hub" {
  project = var.project_id
}

# --- Cloud Router for Interconnect BGP (HA over two VLAN attachments) ---
resource "google_compute_router" "hub" {
  name    = "router-hub"
  project = var.project_id
  region  = var.region
  network = google_compute_network.hub.id
  bgp {
    asn = var.cloud_router_asn
    # advertise the cloud /12 summary only (doc 02 §3.3)
    advertise_mode    = "CUSTOM"
    advertised_groups = []
  }
}

# VLAN attachments to the (pre-provisioned) Dedicated Interconnect.
resource "google_compute_interconnect_attachment" "vlan" {
  for_each = toset(var.interconnect_attachment_names)
  name     = each.value
  project  = var.project_id
  region   = var.region
  router   = google_compute_router.hub.id
  type     = "DEDICATED"
  # interconnect = <ordered out-of-band>  # TODO
}

# eBGP 65000 <-> cloud_router_asn comes up per attachment via router interface + peer.
# resource "google_compute_router_interface" / "google_compute_router_peer" { ... }  # TODO

# --- Egress firewall: default-deny; east-west via hub (doc 02 §4) ---
resource "google_compute_firewall" "deny_egress_default" {
  name      = "deny-egress-default"
  project   = var.project_id
  network   = google_compute_network.hub.id
  direction = "EGRESS"
  priority  = 65000
  deny { protocol = "all" }
  destination_ranges = ["0.0.0.0/0"]
}

# Private Service Connect endpoint for Google APIs (no public API path).
# resource "google_compute_global_address" + "google_compute_global_forwarding_rule" { ... }  # TODO (doc 05)
