output "vpn_gateway_ip" {
  description = "GCP HA VPN gateway public IP (interface 0) — use as strongSwan remote peer."
  value       = google_compute_ha_vpn_gateway.gw.vpn_interfaces[0].ip_address
}

output "bgp_gcp_ip" {
  description = "GCP BGP link-local IP (strongSwan/FRR peers to this)."
  value       = var.bgp_gcp_ip
}

output "bgp_onprem_ip" {
  description = "On-prem BGP link-local IP to assign on the ipsec0 interface."
  value       = var.bgp_onprem_ip
}

output "test_vm_internal_ip" {
  description = "Private IP of the test VM — ping/SSH it over the tunnel."
  value       = google_compute_instance.test.network_interface[0].network_ip
}

output "cloud_router_name" {
  value = google_compute_router.cr.name
}

output "vpn_tunnel_name" {
  value = google_compute_vpn_tunnel.t0.name
}
