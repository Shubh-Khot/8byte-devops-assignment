# Two dashboards, split by the question they answer:
#
#   1. Service health  - "is the app up and fast?"  (what you open during an
#      incident, ordered the way you actually triage: traffic, then errors,
#      then latency, then capacity)
#   2. Platform        - "what is the infrastructure doing?"  (ECS + RDS
#      resource usage, the view you use for capacity planning and cost)
#
# Splitting them this way keeps the incident dashboard free of the twenty
# database gauges you do not need in the first two minutes of an outage.

resource "aws_cloudwatch_dashboard" "service" {
  dashboard_name = "${var.name_prefix}-service-health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = <<-MD
            # ${var.name_prefix} - service health
            Triage order: **traffic** (is anything arriving?) -> **errors** (is it failing?) -> **latency** (is it slow?) -> **capacity** (is it saturated?).
            Runbook: `docs/runbook.md`. Logs: [application log group](https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(var.log_group_name, "/", "$252F")}).
          MD
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Request rate (per minute)"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { label = "requests" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Error rate (%)"
          region = var.region
          view   = "timeSeries"
          period = 60
          # Expressed as a percentage of total requests, not a raw count.
          # 50 errors means nothing without knowing if it was out of 100 or
          # 100,000, and an alarm on a raw count fires on every traffic spike.
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { id = "e5xx", stat = "Sum", visible = false }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { id = "e4xx", stat = "Sum", visible = false }],
            [".", "RequestCount", ".", ".", { id = "total", stat = "Sum", visible = false }],
            [{ expression = "100 * e5xx / MAX([total, 1])", label = "5xx %", id = "r5xx", color = "#d62728" }],
            [{ expression = "100 * e4xx / MAX([total, 1])", label = "4xx %", id = "r4xx", color = "#ff7f0e" }],
          ]
          yAxis = { left = { min = 0, label = "%" } }
          annotations = {
            horizontal = [{ label = "1% SLO burn", value = 1, color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Latency percentiles (s)"
          region = var.region
          view   = "timeSeries"
          period = 60
          # p50 alongside p99 on purpose: p99 alone cannot distinguish
          # "everything got slower" from "one pathological request type".
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p90", label = "p90" }],
            ["...", { stat = "p99", label = "p99", color = "#d62728" }],
          ]
          yAxis = { left = { min = 0 } }
          annotations = {
            horizontal = [{ label = "p99 alarm", value = var.latency_p99_threshold_seconds, color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Healthy vs unhealthy targets"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.target_group_arn_suffix, { label = "healthy", color = "#2ca02c" }],
            [".", "UnHealthyHostCount", ".", ".", ".", ".", { label = "unhealthy", color = "#d62728" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Running tasks"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "running" }],
            [".", "DesiredTaskCount", ".", ".", ".", ".", { label = "desired" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Application errors from logs"
          region = var.region
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
          metrics = [
            [var.custom_metric_namespace, "ApplicationErrors", { label = "ERROR/CRITICAL log lines", color = "#d62728" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Alarm state"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/ApplicationELB", "RejectedConnectionCount", "LoadBalancer", var.alb_arn_suffix, { label = "rejected connections" }],
            [".", "TargetConnectionErrorCount", ".", ".", { label = "target connection errors" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 20
        width  = 24
        height = 7
        properties = {
          title  = "Recent errors and slow requests"
          region = var.region
          # Pre-written so nobody has to remember Logs Insights syntax mid-incident.
          query = <<-Q
            SOURCE '${var.log_group_name}'
            | fields @timestamp, level, msg, request_id, path, status, duration_ms
            | filter level in ["ERROR", "CRITICAL"] or status >= 500 or duration_ms > 1000
            | sort @timestamp desc
            | limit 50
          Q
          view  = "table"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "platform" {
  dashboard_name = "${var.name_prefix}-platform"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = <<-MD
            # ${var.name_prefix} - platform
            Compute and database resource usage. This is the capacity-planning and cost view; for "is the site down?" use the **service-health** dashboard.
          MD
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "ECS service CPU / memory (%)"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "cpu" }],
            [".", "MemoryUtilization", ".", ".", ".", ".", { label = "memory" }],
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "cpu alarm", value = var.ecs_cpu_threshold, color = "#d62728" },
              { label = "scale-out target", value = 65, color = "#2ca02c" },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Task-level CPU/memory reserved vs used"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          # The gap between reserved and used is money. A task reserving 512MB
          # and using 90MB is the signal to halve task_memory.
          metrics = [
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "memory used (MB)" }],
            [".", "MemoryReserved", ".", ".", ".", ".", { label = "memory reserved (MB)" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "RDS CPU (%)"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [{ label = "alarm", value = var.rds_cpu_threshold, color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "RDS connections"
          region = var.region
          view   = "timeSeries"
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_identifier],
          ]
          yAxis = { left = { min = 0 } }
          annotations = {
            horizontal = [{ label = "alarm", value = var.rds_connection_threshold, color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "RDS free storage (GB)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_identifier, { id = "bytes", stat = "Minimum", visible = false }],
            [{ expression = "bytes/1024/1024/1024", label = "free GB", id = "gb" }],
          ]
          yAxis = { left = { min = 0 } }
          annotations = {
            horizontal = [{ label = "alarm", value = var.rds_free_storage_threshold_gb, color = "#d62728" }]
          }
        }
      },
      # Throughput and latency are deliberately two panels, not one with a
      # second y-axis. A dual-axis chart lets you slide two unrelated scales
      # until the lines appear to correlate, and IOPS-vs-seconds is exactly
      # the pairing that fools people.
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS IOPS"
          region = var.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.db_instance_identifier, { stat = "Average", label = "read", color = "#2a78d6" }],
            [".", "WriteIOPS", ".", ".", { stat = "Average", label = "write", color = "#eb6834" }],
          ]
          yAxis = { left = { min = 0, label = "IOPS" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS storage latency (s)"
          region = var.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.db_instance_identifier, { stat = "Average", label = "read", color = "#2a78d6" }],
            [".", "WriteLatency", ".", ".", { stat = "Average", label = "write", color = "#eb6834" }],
          ]
          yAxis = { left = { min = 0, label = "seconds" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "RDS freeable memory (MB)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_instance_identifier, { id = "mem", stat = "Minimum", visible = false }],
            [{ expression = "mem/1024/1024", label = "freeable memory", id = "memmb", color = "#2a78d6" }],
          ]
          yAxis = { left = { min = 0, label = "MB" } }
          annotations = {
            horizontal = [{ label = "alarm", value = var.rds_freeable_memory_threshold_mb, color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU credit balance"
          region = var.region
          view   = "timeSeries"
          period = 300
          # t-class instances run on CPU credits. Watching the balance drain is
          # how you find out you have outgrown a burstable instance, before it
          # throttles you into an outage.
          metrics = [
            ["AWS/RDS", "CPUCreditBalance", "DBInstanceIdentifier", var.db_instance_identifier, { stat = "Minimum", label = "credits remaining", color = "#2a78d6" }],
          ]
          yAxis = { left = { min = 0, label = "credits" } }
          annotations = {
            horizontal = [{ label = "throttling risk", value = 30, color = "#d62728" }]
          }
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "Slowest endpoints (last window)"
          region = var.region
          # Capacity work starts with "what is actually expensive", which is a
          # log query, not a metric - the per-route breakdown only exists in
          # the structured access log.
          query = <<-Q
            SOURCE '${var.log_group_name}'
            | fields route, duration_ms
            | filter ispresent(duration_ms) and ispresent(route)
            | stats count() as requests,
                    avg(duration_ms) as avg_ms,
                    pct(duration_ms, 95) as p95_ms,
                    max(duration_ms) as max_ms
                    by route
            | sort p95_ms desc
            | limit 20
          Q
          view  = "table"
        }
      },
    ]
  })
}
