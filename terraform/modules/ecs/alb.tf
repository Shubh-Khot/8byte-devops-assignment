# Application Load Balancer.
#
# Two target groups exist but only one is wired to the listener. The second is
# there so a blue/green cutover (CodeDeploy, or a manual listener swap) does
# not require creating infrastructure at the moment you most want to move fast.

resource "aws_lb" "this" {
  name               = substr("${var.name_prefix}-alb", 0, 32)
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]

  idle_timeout               = 60
  enable_deletion_protection = var.alb_deletion_protection
  drop_invalid_header_fields = true

  # HTTP desync attacks rely on ambiguous request framing. Anything the ALB
  # cannot parse unambiguously gets dropped rather than forwarded.
  desync_mitigation_mode = "strictest"

  dynamic "access_logs" {
    for_each = var.access_logs_bucket == null ? [] : [1]
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.name_prefix
      enabled = true
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "blue" {
  name        = substr("${var.name_prefix}-tg-blue", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # awsvpc networking: targets are ENI addresses, not instances

  # Drain time. Long enough for in-flight requests to finish, short enough
  # that a rollback is not sitting around waiting for old tasks to leave.
  deregistration_delay = 20

  health_check {
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-tg-blue" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "green" {
  name        = substr("${var.name_prefix}-tg-green", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 20

  health_check {
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-tg-green" })

  lifecycle {
    create_before_destroy = true
  }
}

# With a certificate: HTTP redirects to HTTPS and HTTPS carries the traffic.
# Without one: HTTP serves directly. Staging runs without a domain, so the
# certificate is optional rather than assumed.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [] : [1]
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.blue.arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}
