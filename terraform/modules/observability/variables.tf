variable "name_prefix" {
  description = "Prefix applied to dashboards, alarms and the SNS topic."
  type        = string
}

variable "region" {
  description = "Region the dashboards render metrics from."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix, from the ecs module."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix, from the ecs module."
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "service_name" {
  description = "ECS service name."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "log_group_name" {
  description = "Application log group, used by the metric filter and the Logs Insights widgets."
  type        = string
}

variable "custom_metric_namespace" {
  description = "Namespace for metrics derived from logs."
  type        = string
  default     = "TaskApi"
}

variable "alert_emails" {
  description = "Addresses subscribed to the alert topic. Each must confirm by email before it receives anything."
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook subscribed to the alert topic. Null to disable."
  type        = string
  default     = null
  sensitive   = true
}

variable "error_count_threshold" {
  description = "5xx responses per minute before alarming."
  type        = number
  default     = 5
}

variable "latency_p99_threshold_seconds" {
  description = "p99 latency alarm threshold, in seconds."
  type        = number
  default     = 1.5
}

variable "ecs_cpu_threshold" {
  description = "ECS service CPU alarm threshold (%)."
  type        = number
  default     = 85
}

variable "ecs_memory_threshold" {
  description = "ECS service memory alarm threshold (%)."
  type        = number
  default     = 85
}

variable "rds_cpu_threshold" {
  description = "RDS CPU alarm threshold (%)."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_gb" {
  description = "Alarm when free storage drops below this many GB."
  type        = number
  default     = 4
}

variable "rds_connection_threshold" {
  description = "Alarm above this connection count. db.t3.micro caps out near 85."
  type        = number
  default     = 60
}

variable "rds_freeable_memory_threshold_mb" {
  description = "Alarm when freeable memory drops below this many MB."
  type        = number
  default     = 100
}

variable "app_error_threshold" {
  description = "ERROR/CRITICAL log lines per 5 minutes before alarming."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
