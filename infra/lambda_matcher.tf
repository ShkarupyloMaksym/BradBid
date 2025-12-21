# ============================================================================
# Matcher Lambda Function
# ============================================================================

# IAM Role for Matcher Lambda
resource "aws_iam_role" "matcher_lambda_role" {
  name = "${var.project_name}-matcher-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-matcher-lambda-role"
    Environment = var.environment
  }
}

# IAM Policy for Matcher Lambda - SQS Orders Queue permissions
resource "aws_iam_policy" "matcher_lambda_sqs_orders_policy" {
  name        = "${var.project_name}-matcher-lambda-sqs-orders-policy"
  description = "Policy for Matcher Lambda to receive and delete messages from SQS orders queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.orders_fifo.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-matcher-lambda-sqs-orders-policy"
    Environment = var.environment
  }
}

# IAM Policy for Matcher Lambda - SQS Trades Queue permissions
resource "aws_iam_policy" "matcher_lambda_sqs_trades_policy" {
  name        = "${var.project_name}-matcher-lambda-sqs-trades-policy"
  description = "Policy for Matcher Lambda to send messages to SQS trades queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.trades_fifo.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-matcher-lambda-sqs-trades-policy"
    Environment = var.environment
  }
}

# IAM Policy for Matcher Lambda - DynamoDB permissions
resource "aws_iam_policy" "matcher_lambda_dynamodb_policy" {
  name        = "${var.project_name}-matcher-lambda-dynamodb-policy"
  description = "Policy for Matcher Lambda to write to DynamoDB Trades table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.trades.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-matcher-lambda-dynamodb-policy"
    Environment = var.environment
  }
}

# Attach policies to Matcher Lambda role
resource "aws_iam_role_policy_attachment" "matcher_lambda_sqs_orders_policy_attachment" {
  role       = aws_iam_role.matcher_lambda_role.name
  policy_arn = aws_iam_policy.matcher_lambda_sqs_orders_policy.arn
}

resource "aws_iam_role_policy_attachment" "matcher_lambda_sqs_trades_policy_attachment" {
  role       = aws_iam_role.matcher_lambda_role.name
  policy_arn = aws_iam_policy.matcher_lambda_sqs_trades_policy.arn
}

resource "aws_iam_role_policy_attachment" "matcher_lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.matcher_lambda_role.name
  policy_arn = aws_iam_policy.matcher_lambda_dynamodb_policy.arn
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "matcher_lambda_basic_execution" {
  role       = aws_iam_role.matcher_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC execution role for Lambda to access VPC resources (Redis)
resource "aws_iam_role_policy_attachment" "matcher_lambda_vpc_execution" {
  role       = aws_iam_role.matcher_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Archive the Lambda function code
data "archive_file" "matcher_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/matcher"
  output_path = "${path.module}/.terraform/lambda_packages/matcher_lambda.zip"
}

# Matcher Lambda Function
resource "aws_lambda_function" "matcher_lambda" {
  filename         = data.archive_file.matcher_lambda_zip.output_path
  function_name    = "${var.project_name}-matcher"
  role            = aws_iam_role.matcher_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.matcher_lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 60
  memory_size     = 512

  # VPC Configuration to access Redis
  vpc_config {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      REDIS_HOST         = aws_elasticache_replication_group.redis.primary_endpoint_address
      REDIS_PORT         = aws_elasticache_replication_group.redis.port
      TRADES_TABLE_NAME  = aws_dynamodb_table.trades.name
      TRADES_QUEUE_URL   = aws_sqs_queue.trades_fifo.url
      ENVIRONMENT        = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-matcher-lambda"
    Environment = var.environment
  }
}

# CloudWatch Log Group for Matcher Lambda
resource "aws_cloudwatch_log_group" "matcher_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.matcher_lambda.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-matcher-lambda-logs"
    Environment = var.environment
  }
}

# ============================================================================
# SQS Event Source Mapping (Trigger)
# ============================================================================

# Lambda Event Source Mapping for SQS orders.fifo queue
resource "aws_lambda_event_source_mapping" "matcher_sqs_trigger" {
  event_source_arn = aws_sqs_queue.orders_fifo.arn
  function_name    = aws_lambda_function.matcher_lambda.arn
  
  # Batch settings
  batch_size                         = 1  # Process one order at a time for MVP
  maximum_batching_window_in_seconds = 0  # Process immediately
  
  # Error handling
  function_response_types = ["ReportBatchItemFailures"]
  
  # Enable the trigger
  enabled = true
}

# ============================================================================
# Outputs
# ============================================================================

output "matcher_lambda_arn" {
  description = "ARN of the Matcher Lambda function"
  value       = aws_lambda_function.matcher_lambda.arn
}

output "matcher_lambda_name" {
  description = "Name of the Matcher Lambda function"
  value       = aws_lambda_function.matcher_lambda.function_name
}
