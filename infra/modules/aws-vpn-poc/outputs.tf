# Tunnel endpoints + BGP inside addresses — feed these into strongSwan + FRR.
# AWS gives two tunnels; configure both on-prem for redundancy (one is enough for PoC).

output "tunnel1_address" {
  description = "Tunnel 1 outside (AWS public) IP — strongSwan remote peer."
  value       = aws_vpn_connection.conn.tunnel1_address
}

output "tunnel2_address" {
  description = "Tunnel 2 outside (AWS public) IP."
  value       = aws_vpn_connection.conn.tunnel2_address
}

output "tunnel1_cgw_inside_address" {
  description = "On-prem BGP inside IP for tunnel 1 (assign on the XFRM interface)."
  value       = aws_vpn_connection.conn.tunnel1_cgw_inside_address
}

output "tunnel1_vgw_inside_address" {
  description = "AWS BGP inside IP for tunnel 1 (FRR neighbor)."
  value       = aws_vpn_connection.conn.tunnel1_vgw_inside_address
}

output "tunnel2_cgw_inside_address" {
  value = aws_vpn_connection.conn.tunnel2_cgw_inside_address
}

output "tunnel2_vgw_inside_address" {
  value = aws_vpn_connection.conn.tunnel2_vgw_inside_address
}

output "amazon_side_asn" {
  description = "AWS BGP ASN (FRR remote-as for both tunnels)."
  value       = aws_vpn_gateway.vgw.amazon_side_asn
}
