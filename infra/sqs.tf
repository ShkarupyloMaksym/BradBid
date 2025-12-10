# =============================================================================
# SQS QUEUES
# Cost: First 1M requests/month free, then $0.40 per million requests
# =============================================================================

# SQS Queue for Orders
resource "aws_sqs_queue" "orders_queue" {
  name                       = "orders.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds  = 345600  # 4 days
  visibility_timeout_seconds = 360  # 6 minutes (6x Lambda timeout)

  tags = {
    Name = "OrdersQueue"
  }
}

# SQS Queue for Trades
resource "aws_sqs_queue" "trades_queue" {
  name                       = "trades.fifo"
  fifo_queue                 = true
  content_based_deduplication = true
  message_retention_seconds  = 345600  # 4 days
  visibility_timeout_seconds = 360  # 6 minutes

  tags = {
    Name = "TradesQueue"
  }
}

# Outputs
output "orders_queue_url" {
  description = "URL of the Orders SQS queue"
  value       = aws_sqs_queue.orders_queue.url
}

output "orders_queue_arn" {
  description = "ARN of the Orders SQS queue"
  value       = aws_sqs_queue.orders_queue.arn
}

output "trades_queue_url" {
  description = "URL of the Trades SQS queue"
  value       = aws_sqs_queue.trades_queue.url
}

output "trades_queue_arn" {
  description = "ARN of the Trades SQS queue"
  value       = aws_sqs_queue.trades_queue.arn
}
