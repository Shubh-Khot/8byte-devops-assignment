variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "db_instance_id" {
  type = string
}

variable "alert_emails" {
  description = "Addresses subscribed to the alert topic. Each recipient must confirm the subscription by email."
  type        = list(string)
  default     = []
}
