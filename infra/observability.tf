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
      # SQS Metrics - Orders Queue
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", { "stat" = "Sum", "label" = "Messages Sent" }],
            [".", "NumberOfMessagesReceived", { "stat" = "Sum", "label" = "Messages Received" }],
            [".", "ApproximateNumberOfMessagesVisible", { "stat" = "Average", "label" = "Messages Visible" }],
            [".", "ApproximateAgeOfOldestMessage", { "stat" = "Maximum", "label" = "Oldest Message Age (s)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "SQS Orders Queue Metrics"
          period  = 300
          dimensions = {
            QueueName = aws_sqs_queue.orders_queue.name
          }
        }
      },
      # SQS Metrics - Trades Queue
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", { "stat" = "Sum", "label" = "Messages Sent" }],
            [".", "NumberOfMessagesReceived", { "stat" = "Sum", "label" = "Messages Received" }],
            [".", "ApproximateNumberOfMessagesVisible", { "stat" = "Average", "label" = "Messages Visible" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "SQS Trades Queue Metrics"
          period  = 300
          dimensions = {
            QueueName = aws_sqs_queue.trades_queue.name
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
            ReplicationGroupId = aws_elasticache_replication_group.redis.id
          }
        }
      },
      # SQS Queue Age - Critical Metric
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", { "stat" = "Maximum", "label" = "Max Message Age (s)" }],
            [".", "ApproximateNumberOfMessagesVisible", { "stat" = "Average", "label" = "Messages in Queue" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "SQS Orders Queue Age"
          period  = 300
          dimensions = {
            QueueName = aws_sqs_queue.orders_queue.name
          }
          annotations = {
            horizontal = [
              {
                value     = 300
                label     = "5 minute threshold"
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

# Alarm for SQS Message Age
resource "aws_cloudwatch_metric_alarm" "sqs_age_alarm" {
  alarm_name          = "sqs-orders-age-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300  # 5 minutes in seconds
  alarm_description   = "Alert when SQS message age exceeds 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.orders_queue.name
  }

  tags = {
    Name = "SQS Age Alarm"
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
    ReplicationGroupId = aws_elasticache_replication_group.redis.id
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

