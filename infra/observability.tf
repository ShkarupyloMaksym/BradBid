# =============================================================================
# OBSERVABILITY (CLOUDWATCH DASHBOARD)
# Cost: CloudWatch Dashboards: $3/month per dashboard (first 3 free)
# X-Ray: Free tier: 100K traces/month
# =============================================================================

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "exchange_dashboard" {
  dashboard_name = "Exchange-MVP-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Kinesis Metrics - Orders Stream
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", { "stat" = "Sum", "label" = "Incoming Records" }],
            [".", "GetRecords.IteratorAgeMilliseconds", { "stat" = "Average", "label" = "Iterator Age (ms)" }],
            [".", "PutRecord.Success", { "stat" = "Sum", "label" = "Put Success" }],
            [".", "PutRecord.ThrottledRecords", { "stat" = "Sum", "label" = "Throttled" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Kinesis Orders Stream Metrics"
          period  = 300
        }
      },
      # Kinesis Metrics - Trades Stream
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", { "stat" = "Sum", "label" = "Incoming Records" }],
            [".", "GetRecords.IteratorAgeMilliseconds", { "stat" = "Average", "label" = "Iterator Age (ms)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Kinesis Trades Stream Metrics"
          period  = 300
          dimensions = {
            StreamName = aws_kinesis_stream.trades.name
          }
        }
      },
      # Lambda Ingest Metrics
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "stat" = "Sum", "label" = "Invocations" }],
            [".", "Errors", { "stat" = "Sum", "label" = "Errors" }],
            [".", "Duration", { "stat" = "Average", "label" = "Avg Duration (ms)" }],
            [".", "Throttles", { "stat" = "Sum", "label" = "Throttles" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Ingest Lambda Metrics"
          period  = 300
          dimensions = {
            FunctionName = aws_lambda_function.ingest.function_name
          }
        }
      },
      # Lambda Matcher Metrics
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { "stat" = "Sum", "label" = "Invocations" }],
            [".", "Errors", { "stat" = "Sum", "label" = "Errors" }],
            [".", "Duration", { "stat" = "Average", "label" = "Avg Duration (ms)" }],
            [".", "Throttles", { "stat" = "Sum", "label" = "Throttles" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Matcher Lambda Metrics"
          period  = 300
          dimensions = {
            FunctionName = aws_lambda_function.matcher.function_name
          }
        }
      },
      # DynamoDB Orders Table Metrics
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", { "stat" = "Sum", "label" = "Write Capacity Units" }],
            [".", "ConsumedReadCapacityUnits", { "stat" = "Sum", "label" = "Read Capacity Units" }],
            [".", "ThrottledRequests", { "stat" = "Sum", "label" = "Throttled Requests" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "DynamoDB Orders Table"
          period  = 300
          dimensions = {
            TableName = aws_dynamodb_table.orders.name
          }
        }
      },
      # DynamoDB Trades Table Metrics
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", { "stat" = "Sum", "label" = "Write Capacity Units" }],
            [".", "ConsumedReadCapacityUnits", { "stat" = "Sum", "label" = "Read Capacity Units" }],
            [".", "ThrottledRequests", { "stat" = "Sum", "label" = "Throttled Requests" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "DynamoDB Trades Table"
          period  = 300
          dimensions = {
            TableName = aws_dynamodb_table.trades.name
          }
        }
      },
      # ElastiCache Redis Metrics
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", { "stat" = "Average", "label" = "CPU Utilization (%)" }],
            [".", "NetworkBytesIn", { "stat" = "Sum", "label" = "Network Bytes In" }],
            [".", "NetworkBytesOut", { "stat" = "Sum", "label" = "Network Bytes Out" }],
            [".", "CurrConnections", { "stat" = "Average", "label" = "Current Connections" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ElastiCache Redis Metrics"
          period  = 300
          dimensions = {
            CacheClusterId = aws_elasticache_cluster.redis.cluster_id
          }
        }
      },
      # Kinesis Iterator Age (Lag) - Critical Metric
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", { "stat" = "Maximum", "label" = "Max Iterator Age (ms)" }],
            [".", "GetRecords.IteratorAgeMilliseconds", { "stat" = "Average", "label" = "Avg Iterator Age (ms)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Kinesis Iterator Age (Lag) - Orders Stream"
          period  = 300
          dimensions = {
            StreamName = aws_kinesis_stream.orders.name
          }
          annotations = {
            horizontal = [
              {
                value     = 60000
                label     = "1 minute threshold"
                color     = "#ff0000"
                fill      = "below"
                visible   = true
                yAxis     = "left"
              }
            ]
          }
        }
      }
    ]
  })
}

# CloudWatch Alarms for critical metrics

# Alarm for Kinesis Iterator Age (Lag)
resource "aws_cloudwatch_metric_alarm" "kinesis_lag_alarm" {
  alarm_name          = "kinesis-orders-lag-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Average"
  threshold           = 60000  # 1 minute in milliseconds
  alarm_description   = "Alert when Kinesis iterator age exceeds 1 minute"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.orders.name
  }

  tags = {
    Name = "Kinesis Lag Alarm"
  }
}

# Alarm for Lambda Errors
resource "aws_cloudwatch_metric_alarm" "ingest_lambda_errors" {
  alarm_name          = "ingest-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when Ingest Lambda errors exceed threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.ingest.function_name
  }

  tags = {
    Name = "Ingest Lambda Errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "matcher_lambda_errors" {
  alarm_name          = "matcher-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when Matcher Lambda errors exceed threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.matcher.function_name
  }

  tags = {
    Name = "Matcher Lambda Errors"
  }
}

# Alarm for Redis CPU Utilization
resource "aws_cloudwatch_metric_alarm" "redis_cpu_alarm" {
  alarm_name          = "redis-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when Redis CPU utilization exceeds 80%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  tags = {
    Name = "Redis CPU Alarm"
  }
}

# Output
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch Dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.exchange_dashboard.dashboard_name}"
}

