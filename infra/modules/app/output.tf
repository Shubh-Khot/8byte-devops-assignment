output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "alb_arn_suffix" {
  description = "ALB dimension value for CloudWatch metrics"
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group dimension value for CloudWatch metrics"
  value       = aws_lb_target_group.this.arn_suffix
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}