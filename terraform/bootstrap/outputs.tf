output "state_bucket" {
  description = "Bucket name to put in each environment's backend block."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Copy-paste backend block for a new environment."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "<env>/terraform.tfstate"
        region       = "${var.region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}

output "github_actions_role_arn" {
  description = "Put this in the AWS_DEPLOY_ROLE_ARN repository variable in GitHub."
  value       = var.create_github_oidc ? aws_iam_role.github_actions[0].arn : null
}
