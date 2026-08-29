variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket used for Terraform state"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/repository format"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the deployment role"
  type        = string
  default     = "main"
}

variable "github_owner_id" {
  description = "Numeric id of the repository owner (gh api user --jq .id). GitHub embeds it in the OIDC subject so a deleted and re-registered name cannot inherit this role."
  type        = string
  default     = ""
}

variable "github_repository_id" {
  description = "Numeric id of the repository (gh api repos/OWNER/REPO --jq .id)"
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix the deploy role is allowed to manage IAM roles for"
  type        = string
  default     = "hero"
}
