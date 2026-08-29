variable "name_prefix" {
  description = "Prefix used for naming security resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "app_port" {
  description = "Port used by the application"
  type        = number
  default     = 8000
}