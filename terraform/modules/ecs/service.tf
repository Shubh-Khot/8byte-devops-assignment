data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge(var.tags, { Module = "ecs" })

  # Tasks go in public subnets only when there is no NAT to reach ECR through.
  # They still take no inbound traffic except from the ALB security group, but
  # this is a real reduction in defence in depth and is a staging-only choice.
  task_subnets     = var.tasks_in_public_subnets ? var.public_subnet_ids : var.private_subnet_ids
  assign_public_ip = var.tasks_in_public_subnets

  image = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enhanced" : "disabled"
  }

  tags = local.tags
}

# FARGATE_SPOT is roughly 70% cheaper and can be reclaimed with two minutes of
# notice. Splitting the weights lets staging run mostly on spot while keeping
# one on-demand task so a reclaim event never takes the service to zero.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.on_demand_base
    weight            = var.on_demand_weight
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = var.spot_weight
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = local.image
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
          name          = "http"
        }
      ]

      # Plain configuration goes in environment. Anything sensitive goes in
      # secrets, which ECS resolves at task start - the value never appears in
      # the task definition, in `describe-tasks` output, or in the console.
      environment = [
        { name = "APP_ENV", value = var.environment },
        { name = "DB_HOST", value = var.database_host },
        { name = "DB_PORT", value = tostring(var.database_port) },
        { name = "DB_NAME", value = var.database_name },
        { name = "DB_USER", value = var.database_username },
        { name = "LOG_LEVEL", value = var.log_level },
        { name = "BUILD_SHA", value = var.image_tag },
      ]

      secrets = [
        {
          name = "DB_PASSWORD"
          # The ::password:: suffix pulls one key out of the JSON secret, so
          # the container never sees the host or username fields it does not need.
          valueFrom = "${var.database_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app"
        }
      }

      # Container-level health check, independent of the ALB target group.
      # This one catches a wedged process before the ALB notices, and lets ECS
      # replace the task rather than just stop routing to it.
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:${var.app_port}/healthz').status==200 else 1)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      # Fargate ignores this without platform 1.4+, but it costs nothing to
      # ask for a read-only root filesystem where the app writes nothing.
      readonlyRootFilesystem = var.readonly_root_filesystem
    }
  ])

  tags = local.tags
}

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  propagate_tags  = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = var.on_demand_base
    weight            = var.on_demand_weight
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = var.spot_weight
  }

  network_configuration {
    subnets          = local.task_subnets
    security_groups  = [var.tasks_security_group_id]
    assign_public_ip = local.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.service_name
    container_port   = var.app_port
  }

  # Rolling update with headroom: 200% max lets a full replacement set start
  # before anything is torn down; 100% minimum healthy means capacity never
  # dips during a deploy.
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # This is the deploy safety net. ECS watches the new tasks; if they fail to
  # stabilise it stops the deployment and puts the previous task definition
  # back on its own, without waiting for a human to notice.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Give tasks time to boot and pass health checks before the ALB starts
  # counting failures against them.
  health_check_grace_period_seconds = var.health_check_grace_period

  enable_execute_command = var.enable_execute_command

  # Spread across AZs first, then pack by memory. The order matters: AZ spread
  # is the availability property, binpack is only the cost optimisation.
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  wait_for_steady_state = var.wait_for_steady_state

  # CI deploys by registering a new task definition revision and calling
  # update-service. Terraform would otherwise revert the service to whatever
  # image tag was in the last apply, undoing the most recent deployment.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy.execution_secrets,
  ]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Autoscaling
#
# Two target-tracking policies. CPU is the safety net; requests-per-target is
# the one that actually reacts in time, because a request flood shows up in
# the ALB metric well before it shows up as sustained CPU.
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent

    # Scale out quickly, scale in slowly. Removing capacity too eagerly during
    # a spiky load pattern causes a scale-out/scale-in loop.
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}

resource "aws_appautoscaling_policy" "requests" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-requests-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # The label wants the trailing portion of both ARNs, not the full ARNs.
      resource_label = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.blue.arn_suffix}"
    }
    target_value = var.requests_per_target

    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
