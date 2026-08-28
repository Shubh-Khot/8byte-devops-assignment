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

variable "github_owner_id" {
  description = "Numeric account id of the repository owner, from: gh api user --jq .id. GitHub now embeds it in the OIDC subject so a deleted and re-registered name cannot inherit this role."
  type        = string
  default     = ""
}

variable "github_repository_id" {
  description = "Numeric id of the repository, from: gh api repos/OWNER/REPO --jq .id"
  type        = string
  default     = ""
}
