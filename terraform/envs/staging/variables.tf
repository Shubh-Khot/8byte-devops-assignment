variable "project" {
  description = "Project name, used as the prefix for every resource."
  type        = string
  default     = "taskapi"
}

variable "environment" {
  description = "Environment name, staging or prod."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "availability_zones" {
  description = "Availability zones for the subnets. Set explicitly so no describe call is needed at plan time."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8000
}

variable "image_tag" {
  description = "Image tag to deploy. The pipeline overwrites this on every release."
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "Fargate CPU units per task."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MB per task."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number
  default     = 1
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Run an RDS standby in a second availability zone."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Days of automated RDS backups to keep."
  type        = number
  default     = 7
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot when the database is destroyed."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the database and load balancer from deletion."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "Enable ECS Container Insights."
  type        = bool
  default     = false
}

variable "log_level" {
  description = "Application log level."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

variable "alert_emails" {
  description = "Addresses subscribed to the alert topic."
  type        = list(string)
  default     = []
}

variable "error_threshold" {
  description = "5xx responses per minute before the error alarm fires."
  type        = number
  default     = 5
}
