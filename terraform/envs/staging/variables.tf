variable "project" {
  description = "Project slug, first component of every resource name."
  type        = string
  default     = "taskapi"
}

variable "environment" {
  description = "Environment name. Also becomes APP_ENV inside the container."
  type        = string
  default     = "staging"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Kept distinct from prod so the two can be peered later without renumbering."
  type        = string
  default     = "10.20.0.0/16"
}

variable "service_name" {
  description = "Service name, also the ECR repository name."
  type        = string
  default     = "task-api"
}

variable "app_port" {
  description = "Container port."
  type        = number
  default     = 8000
}

variable "image_tag" {
  description = <<-EOT
    Image tag to run. CI passes the git SHA via -var on each deploy; the
    default only exists so the very first apply has something to reference.
  EOT
  type        = string
  default     = "bootstrap"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_username" {
  description = "Master username. The password is generated and stored in Secrets Manager."
  type        = string
  default     = "taskapp"
}

variable "alb_ingress_cidrs" {
  description = "Who can reach the load balancer. Narrow this to your office/VPN range if staging holds real data."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "alert_emails" {
  description = "Addresses subscribed to CloudWatch alarms."
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for alarms. Passed via TF_VAR_slack_webhook_url, never committed."
  type        = string
  default     = null
  sensitive   = true
}

variable "availability_zones" {
  description = <<-EOT
    Explicit AZ names. Leave empty to discover them automatically, which is
    the better default. Set them when the account's SCP denies
    ec2:DescribeAvailabilityZones, or when you need to pin to specific zones
    because a subnet was created there by hand.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "Specify at least two AZs, or none at all to auto-discover."
  }
}
