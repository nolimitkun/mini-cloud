# GCP VPN PoC: HA VPN gateway + Cloud Router (BGP) to an on-prem strongSwan peer,
# a private subnet, firewall rules, and a test VM with NO external IP.
# Single tunnel (no HA SLA) — sufficient to prove the hub-and-spoke pattern.

terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

# --- Network ---
resource "google_compute_network" "poc" {
  name                    = "vpc-poc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

# Private plane (10.x) — intra-cloud / on-prem (doc 02 §1).
resource "google_compute_subnetwork" "hub" {
  name                     = "subnet-poc-hub"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.poc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# Cross-cloud plane (172.x) — resources approved for cross-cloud reach (doc 02 §1.2).
resource "google_compute_subnetwork" "crosscloud" {
  name                     = "subnet-poc-xcloud"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.poc.id
  ip_cidr_range            = var.crosscloud_cidr
  private_ip_google_access = true
}

# --- HA VPN gateway (cloud side) ---
resource "google_compute_ha_vpn_gateway" "gw" {
  name    = "ha-vpn-poc"
  project = var.project_id
  region  = var.region
  network = google_compute_network.poc.id
}

# --- External peer = on-prem strongSwan public IP ---
resource "google_compute_external_vpn_gateway" "peer" {
  name            = "onprem-peer"
  project         = var.project_id
  redundancy_type = "SINGLE_IP_INTERNALLY_REDUNDANT"
  interface {
    id         = 0
    ip_address = var.onprem_public_ip
  }
}

# --- Cloud Router (BGP, ASN 65020) ---
resource "google_compute_router" "cr" {
  name    = "router-poc"
  project = var.project_id
  region  = var.region
  network = google_compute_network.poc.id
  bgp {
    asn = var.cloud_router_asn
    # default advertise_mode = DEFAULT advertises all VPC subnets — both the
    # private (10.48.0.0/24) and cross-cloud (172.19.16.0/24) subnets.
  }
}

# --- Tunnel (IKEv2, PSK), interface 0 of the HA gateway ---
resource "google_compute_vpn_tunnel" "t0" {
  name                            = "tunnel-poc-0"
  project                         = var.project_id
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.gw.id
  vpn_gateway_interface           = 0
  peer_external_gateway           = google_compute_external_vpn_gateway.peer.id
  peer_external_gateway_interface = 0
  shared_secret                   = var.shared_secret
  router                          = google_compute_router.cr.id
  ike_version                     = 2
}

resource "google_compute_router_interface" "if0" {
  name       = "if-poc-0"
  project    = var.project_id
  region     = var.region
  router     = google_compute_router.cr.name
  ip_range   = "${var.bgp_gcp_ip}/30"
  vpn_tunnel = google_compute_vpn_tunnel.t0.name
}

resource "google_compute_router_peer" "peer0" {
  name            = "peer-poc-0"
  project         = var.project_id
  region          = var.region
  router          = google_compute_router.cr.name
  interface       = google_compute_router_interface.if0.name
  peer_ip_address = var.bgp_onprem_ip
  peer_asn        = var.onprem_asn
}

# --- Firewall: allow on-prem (both planes) in over the tunnel; IAP SSH ---
resource "google_compute_firewall" "from_lan" {
  name          = "allow-from-onprem"
  project       = var.project_id
  network       = google_compute_network.poc.id
  direction     = "INGRESS"
  source_ranges = [var.onprem_lan_cidr, var.onprem_crosscloud_cidr]
  allow { protocol = "icmp" }
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  name          = "allow-iap-ssh"
  project       = var.project_id
  network       = google_compute_network.poc.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Google IAP range
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# --- Test VM with no external IP (private plane) ---
resource "google_compute_instance" "test" {
  name         = "poc-test-vm"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro"
  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.hub.id
    # no access_config block => no external IP (private only)
  }
}

# --- Optional second test VM in the cross-cloud subnet (172.19.16.0/24) ---
# Lets you ping a 172.x address from on-prem to prove the cross-cloud plane
# independently. Off by default to keep the base PoC minimal (one VM).
resource "google_compute_instance" "test_xcloud" {
  count        = var.enable_crosscloud_test_vm ? 1 : 0
  name         = "poc-test-vm-xcloud"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro"
  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.crosscloud.id
    # no access_config block => no external IP
  }
}
