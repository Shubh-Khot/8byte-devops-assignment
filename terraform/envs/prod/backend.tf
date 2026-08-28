terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }

  # Remote state, one key per environment in a shared bucket.
  #
  # `bucket` is intentionally left out and passed with -backend-config at init
  # time, because the name embeds the AWS account id. Committing it would make
  # this repo un-runnable in any other account, which matters as soon as more
  # than one person clones it.
  #
  # use_lockfile replaces the old DynamoDB lock table (Terraform >= 1.10):
  # S3 conditional writes give the same mutual exclusion with one less
  # resource to provision, pay for, and grant IAM on.
  backend "s3" {
    key          = "prod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Tags applied to everything, including resources whose modules forget to.
  # Cost allocation and "who owns this?" both depend on these being universal.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "8byte-devops-assignment"
    }
  }
}
