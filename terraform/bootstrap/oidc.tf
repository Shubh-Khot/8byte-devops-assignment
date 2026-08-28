# GitHub Actions -> AWS without static credentials.
#
# The alternative is putting an access key id and secret in GitHub secrets.
# Those do not expire, do not rotate, and leak through fork PRs, logs, and
# laptops. With OIDC, GitHub mints a short-lived token per job, AWS validates
# it against this provider, and the role's trust policy pins exactly which
# repository and which branch may assume it.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS stopped requiring an accurate thumbprint for this provider in 2023 -
  # it validates the certificate chain itself. The field is still mandatory,
  # so the well-known GitHub value goes here and never needs rotating.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions" }
}

data "aws_iam_policy_document" "github_assume" {
  count = var.create_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The important line. Without a `sub` condition, ANY repository on GitHub
    # can assume this role. Each entry is scoped to a branch or a named
    # environment, so a pull request from a fork cannot deploy.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in var.github_subjects : "repo:${var.github_repository}:${s}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.create_github_oidc ? 1 : 0

  name               = "${var.project}-github-actions"
  description        = "Assumed by GitHub Actions in ${var.github_repository}"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  # An hour is plenty for a deploy and short enough that a leaked token is
  # close to worthless.
  max_session_duration = 3600

  tags = { Name = "${var.project}-github-actions" }
}

# What CI is actually allowed to do: push images, roll the ECS service, and
# read the state bucket. Notably NOT: create VPCs, delete databases, or touch
# IAM. Infrastructure changes are applied by a human with their own credentials.
data "aws_iam_policy_document" "github_deploy" {
  count = var.create_github_oidc ? 1 : 0

  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this call is account-wide by design and takes no resource
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:DescribeImages",
    ]
    resources = ["arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}*"]
  }

  statement {
    sid    = "DeployECSService"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeClusters",
    ]
    resources = ["*"] # RegisterTaskDefinition does not support resource-level scoping
  }

  # Required so the deploy job can register a task definition that references
  # the task roles. Scoped to those two roles, not iam:PassRole on "*", which
  # would be equivalent to handing CI every permission in the account.
  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*-ecs-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadTerraformState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count = var.create_github_oidc ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
