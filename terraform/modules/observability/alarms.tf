# Alarms and the notification path.
#
# Rule I applied when picking these: an alarm must correspond to something a
# human would actually do at 3am. "CPU is 71%" is not that. "Half the fleet is
# failing health checks" is. Everything else belongs on a dashboard, not in a
# pager.

locals {
  tags = merge(var.tags, { Module = "observability" })

  # treat_missing_data matters more than the threshold does. "notBreaching" on
  # an error-rate alarm means no data reads as healthy, which is right: no
  # requests means no errors. On the health-check alarm it would be wrong, so
  # that one uses "breaching".
  common = {
    namespace_alb = "AWS/ApplicationELB"
    namespace_ecs = "AWS/ECS"
    namespace_rds = "AWS/RDS"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value

  # Email subscriptions stay "pending confirmation" until the recipient clicks
  # the link. Terraform reports success either way, so verify in the console.
}

# Slack via an HTTPS endpoint (an incoming webhook, or AWS Chatbot in front of
# the topic). Kept optional so the module works with email only.
resource "aws_sns_topic_subscription" "slack" {
  count = var.slack_webhook_url == null ? 0 : 1

  topic_arn              = aws_sns_topic.alerts.arn
  protocol               = "https"
  endpoint               = var.slack_webhook_url
  endpoint_auto_confirms = true
}

# ---------------------------------------------------------------------------
# Load balancer / application
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name        = "${var.name_prefix}-alb-5xx"
  alarm_description = "The application is returning server errors through the load balancer."

  namespace   = local.common.namespace_alb
  metric_name = "HTTPCode_Target_5XX_Count"
  statistic   = "Sum"
  period      = 60

  # Two consecutive minutes, not one. A single blip during a deploy is normal;
  # two in a row is a pattern.
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.error_count_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name        = "${var.name_prefix}-alb-latency-p99"
  alarm_description = "p99 latency above ${var.latency_p99_threshold_seconds}s - users are feeling it."

  namespace          = local.common.namespace_alb
  metric_name        = "TargetResponseTime"
  extended_statistic = "p99" # averages hide exactly the tail you care about
  period             = 60

  evaluation_periods  = 3
  datapoints_to_alarm = 2 # 2 of 3, so one slow minute does not page anyone
  threshold           = var.latency_p99_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name        = "${var.name_prefix}-unhealthy-targets"
  alarm_description = "Tasks are failing the /readyz check and have been pulled from the target group."

  namespace   = local.common.namespace_alb
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"
  period      = 60

  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  # Missing data here means the target group is reporting nothing at all,
  # which is worse than an unhealthy target, not better.
  treat_missing_data = "breaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

# ---------------------------------------------------------------------------
# ECS
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name        = "${var.name_prefix}-ecs-cpu-high"
  alarm_description = "Service CPU is pinned; autoscaling may already be at max_capacity."

  namespace   = local.common.namespace_ecs
  metric_name = "CPUUtilization"
  statistic   = "Average"
  period      = 300

  evaluation_periods  = 2
  threshold           = var.ecs_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name        = "${var.name_prefix}-ecs-memory-high"
  alarm_description = "Memory approaching the task limit; the container will be OOM-killed if it keeps climbing."

  namespace   = local.common.namespace_ecs
  metric_name = "MemoryUtilization"
  statistic   = "Average"
  period      = 300

  evaluation_periods  = 2
  threshold           = var.ecs_memory_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name        = "${var.name_prefix}-rds-cpu-high"
  alarm_description = "Database CPU sustained high - usually a missing index or a query regression."

  namespace   = local.common.namespace_rds
  metric_name = "CPUUtilization"
  statistic   = "Average"
  period      = 300

  evaluation_periods  = 2
  threshold           = var.rds_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name        = "${var.name_prefix}-rds-storage-low"
  alarm_description = "Free storage below ${var.rds_free_storage_threshold_gb}GB. A full disk stops writes entirely."

  namespace   = local.common.namespace_rds
  metric_name = "FreeStorageSpace"
  statistic   = "Minimum"
  period      = 300

  evaluation_periods  = 1
  threshold           = var.rds_free_storage_threshold_gb * 1024 * 1024 * 1024 # metric is in bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name        = "${var.name_prefix}-rds-connections-high"
  alarm_description = "Connection count near the instance limit. Usually a pool leak, not real load."

  namespace   = local.common.namespace_rds
  metric_name = "DatabaseConnections"
  statistic   = "Maximum"
  period      = 300

  evaluation_periods  = 2
  threshold           = var.rds_connection_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  alarm_name        = "${var.name_prefix}-rds-memory-low"
  alarm_description = "Freeable memory low; Postgres will start spilling sorts to disk."

  namespace   = local.common.namespace_rds
  metric_name = "FreeableMemory"
  statistic   = "Minimum"
  period      = 300

  evaluation_periods  = 2
  threshold           = var.rds_freeable_memory_threshold_mb * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

# ---------------------------------------------------------------------------
# Log-derived metric
#
# Turns ERROR lines in the application log into a CloudWatch metric. This is
# the one alarm that catches failures the load balancer never sees - a
# background job blowing up, or an error the app handles and returns 200 for.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.name_prefix}-app-errors"
  log_group_name = var.log_group_name

  # The app logs JSON, so this matches on a parsed field rather than a
  # substring - no false positives from the word "ERROR" inside a message.
  pattern = "{ $.level = \"ERROR\" || $.level = \"CRITICAL\" }"

  metric_transformation {
    name      = "ApplicationErrors"
    namespace = var.custom_metric_namespace
    value     = "1"
    unit      = "Count"
    # Without this, minutes with no errors report no data instead of zero,
    # and the alarm sits in INSUFFICIENT_DATA rather than OK.
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name        = "${var.name_prefix}-application-errors"
  alarm_description = "Application is logging errors that may not surface as HTTP 5xx."

  namespace   = var.custom_metric_namespace
  metric_name = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name
  statistic   = "Sum"
  period      = 300

  evaluation_periods  = 1
  threshold           = var.app_error_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}
