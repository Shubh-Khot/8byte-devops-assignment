output "db_instance_id" {
  description = "CloudWatch DBInstanceIdentifier dimension value"
  value       = aws_db_instance.this.identifier
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}