variable "name_prefix" {
  description = "Prefix applied to security group names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "app_port" {
  description = "Container port the application listens on."
  type        = number
  default     = 8000
}

variable "ingress_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the load balancer. Defaults to the whole internet,
    which is correct for a public app and wrong for an internal one. Staging
    should normally be narrowed to the office/VPN range.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "database_admin_cidrs" {
  description = "Extra CIDRs allowed to reach Postgres directly. Keep empty unless debugging."
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When null, no HTTPS listener rule is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
