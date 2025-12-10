resource "aws_dynamodb_table" "orders" {
  name         = "Orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "OrderId"
  attribute {
    name = "OrderId"
    type = "S"
  }
}

resource "aws_dynamodb_table" "trades" {
  name         = "Trades"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "TradeId"
  attribute {
    name = "TradeId"
    type = "S"
  }
}

resource "aws_sqs_queue" "orders_queue" {
  name                        = "orders.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
}

resource "aws_sqs_queue" "trades_queue" {
  name                        = "trades.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

# =============================================================================
# S3 Analytics Bucket (Krок 5)
# Bucket for storing trade data for analytics
# =============================================================================
resource "aws_s3_bucket" "analytics_bucket" {
  bucket = "exchange-analytics-${random_id.analytics_bucket.hex}"
}

resource "random_id" "analytics_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket_lifecycle_configuration" "analytics_lifecycle" {
  bucket = aws_s3_bucket.analytics_bucket.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "analytics_bucket" {
  bucket = aws_s3_bucket.analytics_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "analytics_bucket_name" {
  description = "S3 bucket name for analytics data"
  value       = aws_s3_bucket.analytics_bucket.bucket
}

output "analytics_bucket_arn" {
  description = "S3 bucket ARN for analytics data"
  value       = aws_s3_bucket.analytics_bucket.arn
}
