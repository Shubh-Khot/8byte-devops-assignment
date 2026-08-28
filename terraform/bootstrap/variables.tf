variable "project" {
  description = "Project slug used to name the state bucket."
  type        = string
  default     = "taskapi"
}

variable "region" {
  description = "Region the state bucket lives in. Must match the backend blocks in each env."
  type        = string
  default     = "ap-south-1"
}

variable "create_github_oidc" {
  description = "Create the GitHub OIDC provider and CI deploy role."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "owner/repo that may assume the CI role."
  type        = string
  default     = "Shubh-Khot/8byte-devops-assignment"
}

variable "github_subjects" {
  description = <<-EOT
    Which refs and environments may assume the role, as OIDC subject suffixes.
    Deliberately narrow: main branch and the two deployment environments only,
    so a PR from a fork cannot get credentials.
  EOT
  type        = list(string)
  default = [
    "ref:refs/heads/main",
    "environment:staging",
    "environment:production",
  ]
}
