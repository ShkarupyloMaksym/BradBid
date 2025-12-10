# =============================================================================
# ANALYTICS PIPELINE (GLUE & ATHENA)
# Cost: Glue Crawler: $0.44 per DPU-hour, Athena: $5 per TB scanned
# =============================================================================

# IAM Role for Glue Crawler
resource "aws_iam_role" "glue_crawler_role" {
  name = "glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Glue Crawler
resource "aws_iam_role_policy" "glue_crawler_policy" {
  name = "glue-crawler-policy"
  role = aws_iam_role.glue_crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:*"
        ]
      }
    ]
  })
}

# Glue Database
resource "aws_glue_catalog_database" "exchange_db" {
  name        = "exchange_data_lake"
  description = "Database for exchange orders and trades data"
}

# Glue Crawler for Orders
resource "aws_glue_crawler" "orders_crawler" {
  database_name = aws_glue_catalog_database.exchange_db.name
  name          = "orders-crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/orders/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })
}

# Glue Crawler for Trades
resource "aws_glue_crawler" "trades_crawler" {
  database_name = aws_glue_catalog_database.exchange_db.name
  name          = "trades-crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/trades/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })
}

# S3 bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project_name}-athena-results-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "AthenaResults"
  }
}

# Prevent accidental public access
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for Athena results (delete after 30 days)
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "delete-old-results"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# Athena Workgroup
resource "aws_athena_workgroup" "exchange_workgroup" {
  name = "exchange-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/"

      encryption_configuration {
        encryption_option = "SSE_S3"  # S3-managed encryption (free)
      }
    }

    # Cost optimization: use latest engine version
    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = {
    Name = "exchange-analytics"
  }
}

# Outputs
output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.exchange_db.name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.exchange_workgroup.name
}

