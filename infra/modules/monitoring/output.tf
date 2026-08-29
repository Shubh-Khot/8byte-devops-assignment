output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "application_dashboard_name" {
  value = aws_cloudwatch_dashboard.application.dashboard_name
}

output "database_dashboard_name" {
  value = aws_cloudwatch_dashboard.database.dashboard_name
}