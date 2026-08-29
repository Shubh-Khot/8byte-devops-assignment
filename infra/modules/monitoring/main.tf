resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = length(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.name_prefix}-ecs-high-cpu"
  alarm_description   = "ECS service CPU utilization is high"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ECS"
  period             = 300
  statistic          = "Average"
  threshold          = 80

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${var.name_prefix}-ecs-high-memory"
  alarm_description   = "ECS service memory utilization is high"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2
  metric_name        = "MemoryUtilization"
  namespace          = "AWS/ECS"
  period             = 300
  statistic          = "Average"
  threshold          = 80

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx"
  alarm_description   = "ALB is returning 5xx responses"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2
  metric_name        = "HTTPCode_ELB_5XX_Count"
  namespace          = "AWS/ApplicationELB"
  period             = 300
  statistic          = "Sum"
  threshold          = 10

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${var.name_prefix}-alb-unhealthy-targets"
  alarm_description   = "ALB has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2
  metric_name        = "UnHealthyHostCount"
  namespace          = "AWS/ApplicationELB"
  period             = 300
  statistic          = "Average"
  threshold          = 0

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-high-cpu"
  alarm_description   = "RDS CPU utilization is high"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 2
  metric_name        = "CPUUtilization"
  namespace          = "AWS/RDS"
  period             = 300
  statistic          = "Average"
  threshold          = 80

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${var.name_prefix}-application"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "ECS CPU and Memory"
          region = var.aws_region

          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ClusterName",
              var.ecs_cluster_name,
              "ServiceName",
              var.ecs_service_name
            ],
            [
              ".",
              "MemoryUtilization",
              ".",
              ".",
              ".",
              "."
            ]
          ]

          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "ALB Requests"
          region = var.aws_region

          metrics = [
            [
              "AWS/ApplicationELB",
              "RequestCount",
              "LoadBalancer",
              var.alb_arn_suffix
            ]
          ]

          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_dashboard" "database" {
  dashboard_name = "${var.name_prefix}-database"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "RDS CPU"
          region = var.aws_region

          metrics = [
            [
              "AWS/RDS",
              "CPUUtilization",
              "DBInstanceIdentifier",
              var.db_instance_id
            ]
          ]

          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6

        properties = {
          title  = "ALB 5xx Errors"
          region = var.aws_region

          metrics = [
            [
              "AWS/ApplicationELB",
              "HTTPCode_ELB_5XX_Count",
              "LoadBalancer",
              var.alb_arn_suffix
            ]
          ]

          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}