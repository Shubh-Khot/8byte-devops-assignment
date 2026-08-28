variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. taskapi-staging."
  type        = string
}

variable "region" {
  description = "AWS region. Used to build VPC endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a /16 or larger for the /20 subnet split to fit."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be /16 or larger; the module carves /20 subnets out of it."
  }
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Two is the minimum the ALB and RDS subnet group accept."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two AZs are required: ALB and the RDS subnet group both demand it."
  }
}

variable "enable_nat_gateway" {
  description = "Provision NAT gateways so private subnets can reach the internet. ~$32/month each."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all AZs. Cheaper, but a single-AZ failure domain."
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Gateway endpoint for S3. Free, and keeps ECR layer traffic off the NAT."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Ship VPC flow logs (REJECT only) to CloudWatch."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention for the flow log group."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags merged into every resource in this module."
  type        = map(string)
  default     = {}
}
