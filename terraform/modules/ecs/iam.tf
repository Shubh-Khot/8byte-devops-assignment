# Two roles, because they are used at two different times by two different
# actors, and conflating them is how a compromised container ends up able to
# pull every image in the account.
#
#   execution role - used by the ECS agent BEFORE the container starts:
#                    pull the image, read the secret, create the log stream.
#   task role      - used by the application code itself, at runtime.
#
# The task role here is deliberately near-empty. The app talks to Postgres and
# nothing else in AWS, so it gets ECS Exec permissions for debugging and no
# data-plane access at all.

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Confused-deputy guard: this role may only be assumed on behalf of tasks
    # in this account, not by some other tenant's ECS service.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above covers ECR and CloudWatch Logs but not Secrets
# Manager, and it is deliberately scoped to this one secret rather than "*".
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadDatabaseCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.database_secret_arn]
  }

  dynamic "statement" {
    for_each = var.database_kms_key_arn == null ? [] : [1]
    content {
      sid       = "DecryptSecret"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.database_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-database-secret"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

# ECS Exec ("docker exec into a Fargate task"). Worth having: without it the
# only way to inspect a misbehaving task is to redeploy it with more logging.
data "aws_iam_policy_document" "task_exec" {
  statement {
    sid    = "ECSExecSSMChannel"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"] # these SSM messaging actions do not support resource ARNs
  }
}

resource "aws_iam_role_policy" "task_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec.json
}
