# Three security groups chained so that each tier only accepts traffic from
# the tier in front of it. Rules reference the source security group by ID,
# never a CIDR: task IPs change on every deploy, group membership does not.
#
#   internet --> alb_sg --> tasks_sg --> database_sg
#
# Rules are separate resources rather than inline ingress/egress blocks. Inline
# blocks are authoritative for the whole group, so two people editing the same
# SG silently clobber each other's rules on the next apply.

locals {
  tags = merge(var.tags, { Module = "security" })
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Public entry point. Terminates client connections."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = var.certificate_arn == null ? toset([]) : toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# The ALB only ever needs to reach the tasks, so its egress is scoped to the
# task security group rather than the usual allow-all default.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to application tasks"
  referenced_security_group_id = aws_security_group.tasks.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "tasks" {
  name_prefix = "${var.name_prefix}-tasks-"
  description = "Fargate tasks. Reachable only from the load balancer."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-tasks" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "App traffic from the ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# Tasks need outbound 443 to pull images from ECR, read secrets, and ship logs.
# Left broad because those endpoints are a large, changing set of AWS IP ranges;
# tightening it properly means interface VPC endpoints, which cost more than
# this environment justifies. Noted in the README as a known tradeoff.
resource "aws_vpc_security_group_egress_rule" "tasks_https" {
  security_group_id = aws_security_group.tasks.id
  description       = "ECR, Secrets Manager, CloudWatch Logs"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_db" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "Postgres"
  referenced_security_group_id = aws_security_group.database.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "database" {
  name_prefix = "${var.name_prefix}-db-"
  description = "RDS. Ingress from the task security group and nothing else."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-db" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_tasks" {
  security_group_id            = aws_security_group.database.id
  description                  = "Postgres from application tasks"
  referenced_security_group_id = aws_security_group.tasks.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Optional break-glass path for running migrations or a psql session from a
# bastion. Empty by default: the database should not be reachable by a human
# without someone deliberately opening this.
resource "aws_vpc_security_group_ingress_rule" "db_admin" {
  for_each = toset(var.database_admin_cidrs)

  security_group_id = aws_security_group.database.id
  description       = "Break-glass admin access from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# No egress rule on the database group at all. Terraform's default for a
# security group created this way is zero egress, which is what we want:
# a compromised database instance has no outbound path.
