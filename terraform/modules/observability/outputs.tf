output "sns_topic_arn" {
  description = "Alert topic. Subscribe more endpoints to this rather than creating new topics."
  value       = aws_sns_topic.alerts.arn
}

output "service_dashboard_name" {
  description = "Name of the service-health dashboard."
  value       = aws_cloudwatch_dashboard.service.dashboard_name
}

output "platform_dashboard_name" {
  description = "Name of the platform dashboard."
  value       = aws_cloudwatch_dashboard.platform.dashboard_name
}

output "dashboard_urls" {
  description = "Direct console links to both dashboards."
  value = {
    service  = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.service.dashboard_name}"
    platform = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.platform.dashboard_name}"
  }
}

output "alarm_names" {
  description = "Every alarm this module creates, for use in a composite alarm or a status page."
  value = [
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.alb_latency.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_targets.alarm_name,
    aws_cloudwatch_metric_alarm.ecs_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.ecs_memory.alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.rds_storage.alarm_name,
    aws_cloudwatch_metric_alarm.rds_connections.alarm_name,
    aws_cloudwatch_metric_alarm.rds_freeable_memory.alarm_name,
    aws_cloudwatch_metric_alarm.app_errors.alarm_name,
  ]
}
