variable "name_prefix" {
  description = "Prefix applied to resource names, e.g. taskapi-staging."
  type        = string
}

variable "environment" {
  description = "Environment name passed to the container as APP_ENV."
  type        = string
}

variable "service_name" {
  description = "Service and ECR repository name."
  type        = string
  default     = "task-api"
}

variable "vpc_id" {
  description = "VPC the target group resolves targets in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (and for tasks when tasks_in_public_subnets is true)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for tasks. Requires a NAT gateway to reach ECR."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group for the load balancer."
  type        = string
}

variable "tasks_security_group_id" {
  description = "Security group for the Fargate tasks."
  type        = string
}

variable "tasks_in_public_subnets" {
  description = <<-EOT
    Run tasks in public subnets with a public IP so they can reach ECR without
    a NAT gateway. Saves ~$32/month. Tasks still accept no inbound traffic
    except from the ALB security group, but this is weaker isolation and
    should stay false in production.
  EOT
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Image tag to deploy. CI overrides this per release; the default is only for a first apply."
  type        = string
  default     = "bootstrap"
}

variable "app_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Target group health check path. Readiness, not liveness: it must fail when dependencies are down."
  type        = string
  default     = "/readyz"
}

variable "task_cpu" {
  description = "Task CPU units. 256 = 0.25 vCPU."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MiB. Must be a valid pairing with task_cpu."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. ARM64 (Graviton) is ~20% cheaper but needs a matching image build."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  description = "Initial task count. Ignored after creation; autoscaling owns it from then on."
  type        = number
  default     = 2
}

variable "enable_autoscaling" {
  description = "Attach target-tracking autoscaling policies to the service."
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Autoscaling floor. Two tasks means one AZ can fail without an outage."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Autoscaling ceiling. Also the blast radius on your bill."
  type        = number
  default     = 6
}

variable "cpu_target_percent" {
  description = "Target average CPU for the scaling policy."
  type        = number
  default     = 65
}

variable "requests_per_target" {
  description = "Target requests per task per minute for the ALB scaling policy."
  type        = number
  default     = 1000
}

variable "on_demand_base" {
  description = "Tasks always placed on on-demand Fargate before spot is used at all."
  type        = number
  default     = 1
}

variable "on_demand_weight" {
  description = "Relative share of additional tasks placed on on-demand."
  type        = number
  default     = 1
}

variable "spot_weight" {
  description = "Relative share of additional tasks placed on Fargate Spot. 0 disables spot."
  type        = number
  default     = 0
}

variable "database_host" {
  description = "RDS hostname."
  type        = string
}

variable "database_port" {
  description = "RDS port."
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Database name."
  type        = string
}

variable "database_username" {
  description = "Database username. Not a secret; the password is."
  type        = string
}

variable "database_secret_arn" {
  description = "Secrets Manager ARN holding the credentials JSON."
  type        = string
}

variable "database_kms_key_arn" {
  description = "CMK protecting the secret, if any. Adds kms:Decrypt to the execution role."
  type        = string
  default     = null
}

variable "log_level" {
  description = "Application log level."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch log retention. Never leave this unset - the default is forever."
  type        = number
  default     = 30
}

variable "container_insights" {
  description = "Container Insights. Gives per-task CPU/memory metrics; bills per metric."
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Allow ECS Exec into running tasks. Audited via CloudTrail."
  type        = bool
  default     = true
}

variable "readonly_root_filesystem" {
  description = "Mount the container root filesystem read-only."
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Seconds before the ALB health check counts against a new task."
  type        = number
  default     = 60
}

variable "wait_for_steady_state" {
  description = "Make terraform apply block until the service stabilises."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When null the ALB serves plain HTTP - acceptable for staging without a domain."
  type        = string
  default     = null
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs. Null disables them."
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "Block accidental deletion of the load balancer."
  type        = bool
  default     = false
}

variable "ecr_keep_images" {
  description = "Number of tagged images to retain in ECR."
  type        = number
  default     = 15
}

variable "ecr_force_delete" {
  description = "Allow destroying the ECR repository while it still holds images."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
