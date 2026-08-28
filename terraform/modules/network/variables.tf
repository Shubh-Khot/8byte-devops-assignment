variable "name" {
  description = "Prefix for resource names, for example taskapi-staging."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones to spread the subnets across."
  type        = list(string)
}
