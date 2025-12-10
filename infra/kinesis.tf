# =============================================================================
# KINESIS DATA STREAMS & FIREHOSE
# Cost: ~$0.015 per shard/hour = ~$11/month per shard (1 shard each = ~$22/month)
# Using 1 shard per stream to minimize costs
# =============================================================================

# Kinesis Data Stream for Orders
resource "aws_kinesis_stream" "orders" {
  name             = "KDS_Orders"
  shard_count      = 1  # Minimum for cost savings
  retention_period = 24  # Hours (minimum)

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  tags = {
    Name = "KDS_Orders"
  }
}

# Kinesis Data Stream for Trades
resource "aws_kinesis_stream" "trades" {
  name             = "KDS_Trades"
  shard_count      = 1  # Minimum for cost savings
  retention_period = 24  # Hours (minimum)

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  tags = {
    Name = "KDS_Trades"
  }
}

# IAM Role for Firehose to write to S3
resource "aws_iam_role" "firehose_delivery_role" {
  name = "firehose-delivery-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Firehose to access S3 and Kinesis
resource "aws_iam_role_policy" "firehose_delivery_policy" {
  name = "firehose-delivery-policy"
  role = aws_iam_role.firehose_delivery_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = [
          aws_kinesis_stream.orders.arn,
          aws_kinesis_stream.trades.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws/kinesisfirehose/*"
        ]
      }
    ]
  })
}

# Kinesis Firehose Delivery Stream for Orders
resource "aws_kinesis_firehose_delivery_stream" "orders_to_s3" {
  name        = "firehose-orders-to-s3"
  destination = "s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.orders.arn
    role_arn           = aws_iam_role.firehose_delivery_role.arn
  }

  s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.data_lake.arn
    prefix             = "orders/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/orders/"

    buffer_size     = 5    # MB
    buffer_interval = 60   # seconds (minimum for cost savings)

    compression_format = "GZIP"  # Reduce storage costs

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_orders.name
    }
  }
}

# Kinesis Firehose Delivery Stream for Trades
resource "aws_kinesis_firehose_delivery_stream" "trades_to_s3" {
  name        = "firehose-trades-to-s3"
  destination = "s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.trades.arn
    role_arn           = aws_iam_role.firehose_delivery_role.arn
  }

  s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.data_lake.arn
    prefix             = "trades/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/trades/"

    buffer_size     = 5    # MB
    buffer_interval = 60   # seconds (minimum for cost savings)

    compression_format = "GZIP"  # Reduce storage costs

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_trades.name
    }
  }
}

# CloudWatch Log Groups for Firehose
resource "aws_cloudwatch_log_group" "firehose_orders" {
  name              = "/aws/kinesisfirehose/firehose-orders-to-s3"
  retention_in_days = 7  # Keep logs for 7 days to save costs
}

resource "aws_cloudwatch_log_group" "firehose_trades" {
  name              = "/aws/kinesisfirehose/firehose-trades-to-s3"
  retention_in_days = 7  # Keep logs for 7 days to save costs
}

# Outputs
output "kinesis_orders_stream_arn" {
  description = "ARN of the Kinesis Orders stream"
  value       = aws_kinesis_stream.orders.arn
}

output "kinesis_orders_stream_name" {
  description = "Name of the Kinesis Orders stream"
  value       = aws_kinesis_stream.orders.name
}

output "kinesis_trades_stream_arn" {
  description = "ARN of the Kinesis Trades stream"
  value       = aws_kinesis_stream.trades.arn
}

output "kinesis_trades_stream_name" {
  description = "Name of the Kinesis Trades stream"
  value       = aws_kinesis_stream.trades.name
}

