# =============================================================================
# DYNAMODB TABLES
# Cost: On-Demand billing (pay per request) - Free tier: 25 WCU/RCU
# =============================================================================

resource "aws_dynamodb_table" "orders" {
  name         = "Orders"
  billing_mode = "PAY_PER_REQUEST"  # On-Demand for cost efficiency
  hash_key     = "OrderId"
  
  attribute {
    name = "OrderId"
    type = "S"
  }

  # Point-in-time recovery disabled to save costs
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Name = "Orders"
  }
}

resource "aws_dynamodb_table" "trades" {
  name         = "Trades"
  billing_mode = "PAY_PER_REQUEST"  # On-Demand for cost efficiency
  hash_key     = "TradeId"
  
  attribute {
    name = "TradeId"
    type = "S"
  }

  # Point-in-time recovery disabled to save costs
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Name = "Trades"
  }
}

# =============================================================================
# S3 DATA LAKE
# Cost: ~$0.023 per GB/month (Standard storage)
# =============================================================================

resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-data-lake-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "DataLake"
  }
}

# Prevent accidental public access
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning disabled to save costs
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Disabled"
  }
}

# Lifecycle policy to transition to cheaper storage and delete old data
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER_IR"  # Glacier Instant Retrieval - cheaper for infrequent access
    }
  }

  rule {
    id     = "delete-old-data"
    status = "Enabled"

    expiration {
      days = 90  # Delete data older than 90 days to save costs
    }
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # S3-managed keys (free)
    }
  }
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Variable for project name
variable "project_name" {
  description = "Project name for resource naming"
  default     = "bidding-exchange"
  type        = string
}

# Outputs
output "s3_data_lake_bucket_name" {
  description = "Name of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.id
}

output "s3_data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.arn
}
