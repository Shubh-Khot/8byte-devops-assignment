output "endpoint" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "password_secret_arn" {
  description = "Secrets Manager secret holding the master credentials, rotated by RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
