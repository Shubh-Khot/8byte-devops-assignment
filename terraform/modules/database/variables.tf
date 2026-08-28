variable "name_prefix" {
  description = "Prefix applied to database resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Data-tier subnet IDs. Must span at least two AZs."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for the instance, from the security module."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major.minor version."
  type        = string
  default     = "16.4"
}

variable "parameter_group_family" {
  description = "Parameter group family. Must match the major version of engine_version."
  type        = string
  default     = "postgres16"
}

variable "instance_class" {
  description = "RDS instance class. db.t3.micro is free-tier eligible for the first 12 months."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB. 20 is the free-tier allowance."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB. Set equal to allocated_storage to disable."
  type        = number
  default     = 50
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "tasksdb"
}

variable "master_username" {
  description = "Master username. Cannot be 'postgres', 'admin', or 'rdsadmin'."
  type        = string
  default     = "taskapp"

  validation {
    condition     = !contains(["postgres", "admin", "rdsadmin"], lower(var.master_username))
    error_message = "RDS reserves postgres, admin and rdsadmin as master usernames."
  }
}

variable "multi_az" {
  description = "Standby in a second AZ. Roughly doubles cost; buys automatic failover."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups. Also the point-in-time-recovery window. 0 disables backups entirely."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Backups must be enabled; 0 also silently disables point-in-time recovery."
  }
}

variable "backup_window" {
  description = "Daily backup window in UTC. Kept off peak for IST-hours traffic."
  type        = string
  default     = "18:00-19:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC. Must not overlap backup_window."
  type        = string
  default     = "Sun:19:30-Sun:20:30"
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. True only in throwaway environments."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block `terraform destroy` from deleting the instance."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Performance Insights. Free at 7 days retention."
  type        = bool
  default     = true
}

variable "enhanced_monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds (0, 1, 5, 10, 15, 30, 60). 0 disables it."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enhanced_monitoring_interval)
    error_message = "Must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "slow_query_threshold_ms" {
  description = "Log statements slower than this. -1 disables slow query logging."
  type        = number
  default     = 500
}

variable "create_kms_key" {
  description = "Create a customer-managed KMS key. When false, AWS-managed keys are used."
  type        = bool
  default     = false
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window. 0 deletes immediately, which is what you want in staging."
  type        = number
  default     = 7
}

variable "apply_immediately" {
  description = "Apply changes now instead of during the maintenance window. Can cause downtime."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
