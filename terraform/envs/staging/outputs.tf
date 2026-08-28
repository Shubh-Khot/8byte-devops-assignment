output "app_url" {
  description = "Public URL of the staging service."
  value       = "http://${module.ecs.alb_dns_name}"
}

output "alb_dns_name" {
  description = "Load balancer hostname."
  value       = module.ecs.alb_dns_name
}

output "ecr_repository_url" {
  description = "Where CI pushes images."
  value       = module.ecs.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "Cluster name, used by the deploy job."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Service name, used by the deploy job."
  value       = module.ecs.service_name
}

output "task_definition_family" {
  description = "Task definition family CI registers revisions against."
  value       = module.ecs.task_definition_family
}

output "database_endpoint" {
  description = "RDS endpoint. Not reachable from outside the VPC."
  value       = module.database.endpoint
}

output "database_secret_name" {
  description = "Secrets Manager entry holding the database credentials."
  value       = module.database.secret_name
}

output "log_group" {
  description = "CloudWatch log group for application logs."
  value       = module.ecs.log_group_name
}

output "dashboards" {
  description = "Console links to the two CloudWatch dashboards."
  value       = module.observability.dashboard_urls
}

output "alert_topic_arn" {
  description = "SNS topic alarms publish to."
  value       = module.observability.sns_topic_arn
}

output "vpc_id" {
  description = "VPC id, handy for manual debugging."
  value       = module.network.vpc_id
}
