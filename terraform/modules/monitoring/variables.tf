variable "name" {
  description = "Prefix for alarm and dashboard names."
  type        = string
}

variable "region" {
  description = "Region the dashboard widgets query."
  type        = string
}

variable "alb_arn_suffix" {
  description = "Load balancer dimension for the ALB metrics."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group dimension for the health check metric."
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

variable "db_identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "alert_emails" {
  description = "Addresses subscribed to the SNS topic. Each needs to confirm by email."
  type        = list(string)
  default     = []
}

variable "error_threshold" {
  description = "5xx responses per minute before the alarm fires."
  type        = number
  default     = 5
}

variable "latency_threshold_seconds" {
  description = "p95 latency in seconds before the alarm fires."
  type        = number
  default     = 1
}

variable "rds_free_storage_threshold_gb" {
  description = "Free storage in GB before the alarm fires."
  type        = number
  default     = 5
}
