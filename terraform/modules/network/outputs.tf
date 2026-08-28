output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR of the VPC, for security group rules that need it."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnets, one per AZ. The ALB lives here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets, one per AZ. Fargate tasks live here when NAT is enabled."
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "Data subnets, one per AZ. RDS only, no internet route."
  value       = aws_subnet.data[*].id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs, empty when NAT is disabled."
  value       = aws_nat_gateway.this[*].id
}
