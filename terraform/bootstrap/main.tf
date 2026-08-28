# Chicken-and-egg: the backend that stores Terraform state cannot itself be
# stored in that backend. This root module runs ONCE with local state, creates
# the bucket, and then its own state file is committed alongside it.
#
# Everything here is destroy-protected on purpose. Losing this bucket means
# losing the record of every resource Terraform manages.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "tf-state"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are globally unique across all of AWS, so the account id is
  # appended rather than hoping "taskapi-tfstate" happens to be free.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Refuse to delete a bucket that still has state files in it. Removing this
  # line is a deliberate act, which is the point.
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the actual disaster recovery story for Terraform state. A
# corrupted or truncated state file is recoverable by restoring the previous
# object version; without versioning it is not recoverable at all.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# State contains generated database passwords and every resource identifier in
# the account. Treated as a secret, so all four public-access switches are on.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    # Keep 90 days of history: long enough to recover from a bad apply nobody
    # noticed for a while, short enough that the bucket does not grow forever.
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Deny any request that is not over TLS. S3 is encrypted at rest by default,
# but nothing stops a client from talking plain HTTP to it without this.
data "aws_iam_policy_document" "state" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}

# ---------------------------------------------------------------------------
# Locking
#
# No DynamoDB table here. Since Terraform 1.10 the S3 backend can lock using a
# conditional-write lock file in the bucket itself (`use_lockfile = true`),
# which removes a whole resource, its IAM policy, and its bill. The DynamoDB
# approach is still what most existing repos use, and `dynamodb_table` is now
# deprecated in the backend config - worth knowing which one you are looking
# at when you inherit a codebase.
# ---------------------------------------------------------------------------
