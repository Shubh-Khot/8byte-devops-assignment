output "endpoint" {
  description = "Connection endpoint, host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the instance listens on."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "identifier" {
  description = "RDS instance identifier, used by CloudWatch alarm dimensions."
  value       = aws_db_instance.this.identifier
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the credentials. ECS reads from this."
  value       = aws_secretsmanager_secret.credentials.arn
}

output "secret_name" {
  description = "Name of the credential secret, for the AWS CLI."
  value       = aws_secretsmanager_secret.credentials.name
}

output "kms_key_arn" {
  description = "CMK protecting storage and the secret, null when using AWS-managed keys."
  value       = var.create_kms_key ? aws_kms_key.database[0].arn : null
}

# Deliberately not output: the password. It is in Secrets Manager, which is
# the one place that should hand it out.
