variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name passed to the container as APP_ENV."
  type        = string
}

variable "region" {
  description = "Region, used by the awslogs driver."
  type        = string
}

variable "vpc_id" {
  description = "VPC the target group lives in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets for the load balancer."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets for the ECS tasks."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the load balancer."
  type        = string
}

variable "app_security_group_id" {
  description = "Security group for the ECS tasks."
  type        = string
}

variable "image" {
  description = "Full image URI including the tag."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8000
}

variable "cpu" {
  description = "Fargate CPU units for the task."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MB for the task."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "db_host" {
  description = "Database endpoint."
  type        = string
}

variable "db_port" {
  description = "Database port."
  type        = number
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_username" {
  description = "Database user."
  type        = string
}

variable "db_password_secret_arn" {
  description = "Secrets Manager ARN holding the database credentials."
  type        = string
}

variable "log_level" {
  description = "Application log level."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}

variable "container_insights" {
  description = "Enable ECS Container Insights. Costs extra, so staging leaves it off."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Refuse to delete the load balancer through the API."
  type        = bool
  default     = false
}
