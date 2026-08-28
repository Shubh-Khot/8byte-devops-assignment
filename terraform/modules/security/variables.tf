variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
}
