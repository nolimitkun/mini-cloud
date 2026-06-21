output "vpc_id" {
  description = "Spoke VPC ID."
  value       = aws_vpc.spoke.id
}

output "private_subnet_ids" {
  description = "Map of AZ → private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "crosscloud_subnet_id" {
  description = "Cross-cloud subnet ID."
  value       = aws_subnet.crosscloud.id
}

output "tgw_attachment_id" {
  description = "TGW VPC attachment ID."
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}
