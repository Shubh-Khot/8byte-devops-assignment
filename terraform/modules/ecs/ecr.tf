# Image registry.
#
# Lifecycle policy is not optional housekeeping: CI pushes an image tagged
# with the git SHA on every merge, so without expiry this repository grows
# forever and you pay storage on images nobody can even name.

resource "aws_ecr_repository" "this" {
  name = var.service_name

  # Immutable tags mean a given SHA tag can never be overwritten to point at
  # different bytes. "Which code is in production?" then has one answer.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true # basic CVE scan; the pipeline also runs Trivy pre-push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = var.ecr_force_delete

  tags = merge(local.tags, { Name = var.service_name })
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.ecr_keep_images} release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_keep_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged layers after 3 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 3
        }
        action = { type = "expire" }
      },
    ]
  })
}
