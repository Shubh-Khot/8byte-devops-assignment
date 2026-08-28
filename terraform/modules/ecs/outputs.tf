output "alb_dns_name" {
  description = "Public hostname of the load balancer. This is the app URL."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone of the ALB, for a Route53 alias record."
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix. CloudWatch alarm and dashboard dimensions need this form."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, for CloudWatch dimensions."
  value       = aws_lb_target_group.blue.arn_suffix
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name. Used by the deploy job."
  value       = aws_ecs_service.this.name
}

output "task_definition_family" {
  description = "Task definition family. CI registers new revisions against it."
  value       = aws_ecs_task_definition.this.family
}

output "ecr_repository_url" {
  description = "ECR repository URL that CI pushes to."
  value       = aws_ecr_repository.this.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.this.name
}

output "log_group_name" {
  description = "CloudWatch log group holding application logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "execution_role_arn" {
  description = "ECS execution role ARN."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN."
  value       = aws_iam_role.task.arn
}
