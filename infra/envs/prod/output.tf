output "app_url" {
  description = "Public URL of the service"
  value       = "http://${module.app.alb_dns_name}"
}

output "image" {
  description = "Image URI the service is configured with"
  value       = local.container_image
}

output "ecs_cluster_name" {
  value = module.app.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.app.ecs_service_name
}

output "database_endpoint" {
  value = module.database.db_endpoint
}

output "alerts_topic_arn" {
  value = module.monitoring.sns_topic_arn
}
