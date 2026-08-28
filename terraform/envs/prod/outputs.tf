output "app_url" {
  description = "Public URL of the service."
  value       = "http://${module.app.alb_dns_name}"
}

output "image" {
  description = "Image URI the service is running."
  value       = local.image
}

output "ecs_cluster_name" {
  value = module.app.cluster_name
}

output "ecs_service_name" {
  value = module.app.service_name
}

output "log_group_name" {
  value = module.app.log_group_name
}

output "database_endpoint" {
  value = module.database.endpoint
}

output "dashboard_url" {
  value = module.monitoring.dashboard_url
}
