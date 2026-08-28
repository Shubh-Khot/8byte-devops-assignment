output "alb_security_group_id" {
  description = "Security group attached to the load balancer."
  value       = aws_security_group.alb.id
}

output "tasks_security_group_id" {
  description = "Security group attached to the Fargate tasks."
  value       = aws_security_group.tasks.id
}

output "database_security_group_id" {
  description = "Security group attached to the RDS instance."
  value       = aws_security_group.database.id
}
