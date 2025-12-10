# =============================================================================
# ANALYTICS LAYER (Krок 9)
# Firehose, Glue, and Athena for trade data analytics
# =============================================================================

# -----------------------------------------------------------------------------
# Kinesis Firehose for streaming trade data to S3
# -----------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "trades_firehose" {
  name        = "exchange-trades-firehose"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.analytics_bucket.arn
    prefix             = "trades/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    
    buffering_size     = 5   # 5 MB minimum
    buffering_interval = 300 # 5 minutes for cost optimization

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
      log_stream_name = "S3Delivery"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose_logs" {
  name              = "/aws/kinesisfirehose/exchange-trades"
  retention_in_days = 7
}

# IAM Role for Firehose
resource "aws_iam_role" "firehose_role" {
  name = "exchange_firehose_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "firehose_s3_access"
  role = aws_iam_role.firehose_role.id

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
          aws_s3_bucket.analytics_bucket.arn,
          "${aws_s3_bucket.analytics_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose_logs.arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Glue Database and Crawler for trade data
# -----------------------------------------------------------------------------
resource "aws_glue_catalog_database" "trades_db" {
  name = "exchange_trades_db"
}

resource "aws_glue_crawler" "trades_crawler" {
  database_name = aws_glue_catalog_database.trades_db.name
  name          = "exchange-trades-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.analytics_bucket.bucket}/trades/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  schedule = "cron(0 0 * * ? *)" # Run daily at midnight
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "exchange_glue_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "glue_s3_access"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.analytics_bucket.arn,
          "${aws_s3_bucket.analytics_bucket.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Athena Workgroup for querying trade data
# -----------------------------------------------------------------------------
resource "aws_athena_workgroup" "trades_workgroup" {
  name = "exchange-trades-workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.analytics_bucket.bucket}/athena-results/"
    }

    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
  }

  force_destroy = true
}

# Outputs
output "firehose_delivery_stream_name" {
  description = "Name of the Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.trades_firehose.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.trades_firehose.arn
}

output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.trades_db.name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.trades_workgroup.name
}
