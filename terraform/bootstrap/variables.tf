variable "project" {
  description = "Project name, used as the prefix for bootstrap resources."
  type        = string
  default     = "taskapi"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "Globally unique bucket name for Terraform state."
  type        = string
}

variable "github_repository" {
  description = "Repository allowed to assume the deployment role, as owner/name."
  type        = string
}
