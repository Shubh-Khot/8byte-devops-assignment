variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the database subnet group."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group allowing Postgres from the application only."
  type        = string
}

variable "engine_version" {
  description = "Postgres major version."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GB. Autoscales up to three times this value."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the database to create."
  type        = string
  default     = "tasksdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored in Secrets Manager by RDS."
  type        = string
  default     = "tasks"
}

variable "multi_az" {
  description = "Run a standby in a second availability zone."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Refuse to delete the instance through the API."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy."
  type        = bool
  default     = true
}
