output "transit_gateway_id" {
  description = "TGW id for spoke attachments."
  value       = aws_ec2_transit_gateway.hub.id
}

output "hub_route_table_id" {
  description = "TGW hub route table id."
  value       = aws_ec2_transit_gateway_route_table.hub.id
}

output "firewall_endpoint_vpc_id" {
  description = "Inspection VPC id (default route target for spokes)."
  value       = aws_vpc.inspection.id
}
