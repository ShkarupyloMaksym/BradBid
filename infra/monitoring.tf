# =============================================================================
# MONITORING & OBSERVABILITY (Krок 10)
# CloudWatch Dashboards, Alarms, and Logs
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda functions
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ingest_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "matcher_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.matcher.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "ws_handler_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ws_handler.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "trade_broadcaster_logs" {
  name              = "/aws/lambda/${aws_lambda_function.trade_broadcaster.function_name}"
  retention_in_days = 7
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for SQS Queue Depth
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "orders_queue_depth" {
  alarm_name          = "orders-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Orders queue has too many pending messages"
  
  dimensions = {
    QueueName = aws_sqs_queue.orders_queue.name
  }
}

resource "aws_cloudwatch_metric_alarm" "trades_queue_depth" {
  alarm_name          = "trades-queue-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  alarm_description   = "Trades queue has too many pending messages"
  
  dimensions = {
    QueueName = aws_sqs_queue.trades_queue.name
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for Lambda Errors
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ingest_lambda_errors" {
  alarm_name          = "ingest-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Ingest Lambda has errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.ingest.function_name
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
  alarm_description   = "Matcher Lambda has errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.matcher.function_name
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "exchange_dashboard" {
  dashboard_name = "ExchangeDashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "SQS Queue Depth"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.orders_queue.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.trades_queue.name]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingest.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.matcher.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ws_handler.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.trade_broadcaster.function_name]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ingest.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.matcher.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.ws_handler.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.trade_broadcaster.function_name]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ingest.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.matcher.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ws_handler.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.trade_broadcaster.function_name]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Read/Write Units"
          region = var.aws_region
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.orders.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.orders.name],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.trades.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.trades.name]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Redis Cache Metrics"
          region = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id],
            ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id],
            ["AWS/ElastiCache", "CacheHits", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id],
            ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "API Gateway Metrics"
          region = var.aws_region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.http_api.id],
            ["AWS/ApiGateway", "4XXError", "ApiId", aws_apigatewayv2_api.http_api.id],
            ["AWS/ApiGateway", "5XXError", "ApiId", aws_apigatewayv2_api.http_api.id],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.http_api.id]
          ]
          period = 60
          stat   = "Sum"
        }
      }
    ]
  })
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.exchange_dashboard.dashboard_name}"
}
