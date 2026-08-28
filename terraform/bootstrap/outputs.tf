output "state_bucket" {
  description = "Pass this to terraform init with -backend-config=bucket=..."
  value       = aws_s3_bucket.state.id
}

output "github_actions_role_arn" {
  description = "Store as the AWS_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_repository_url" {
  description = "Repository the pipeline pushes images to."
  value       = aws_ecr_repository.app.repository_url
}
