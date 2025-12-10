# =============================================================================
# LAMBDA FUNCTIONS
# Cost: Free tier: 1M requests/month, 400K GB-seconds compute
# =============================================================================

# Archive Ingest Lambda code
data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/ingest"
  output_path = "${path.module}/ingest_lambda.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache"]
}

# Archive Matcher Lambda code
data "archive_file" "matcher_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/matcher"
  output_path = "${path.module}/matcher_lambda.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache"]
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "exchange_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Least-privilege IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "exchange_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.orders_queue.arn,
          aws_sqs_queue.trades_queue.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.orders.arn,
          aws_dynamodb_table.trades.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.redis_auth.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach VPC execution role (for Lambda to access VPC resources)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Ingest Lambda - Validates and ingests orders
resource "aws_lambda_function" "ingest" {
  filename         = data.archive_file.ingest_zip.output_path
  function_name    = "ExchangeIngest"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 15
  memory_size      = 256  # Minimum for cost savings
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256

  # X-Ray tracing enabled
  tracing_config {
    mode = "Active"
  }

  # No VPC config needed for Ingest (API Gateway doesn't require VPC)
  # VPC config removed to reduce cold start time and costs

  environment {
    variables = {
      ORDERS_QUEUE_URL = aws_sqs_queue.orders_queue.url
      DYNAMODB_ORDERS_TABLE = aws_dynamodb_table.orders.name
      AWS_XRAY_CONTEXT_MISSING = "LOG_ERROR"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.ingest_lambda
  ]
}

# Matcher Lambda - Processes orders and matches trades
resource "aws_lambda_function" "matcher" {
  filename         = data.archive_file.matcher_zip.output_path
  function_name    = "ExchangeMatcher"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60  # Increased for Redis operations
  memory_size      = 512  # More memory for order book operations
  source_code_hash = data.archive_file.matcher_zip.output_base64sha256

  # X-Ray tracing enabled
  tracing_config {
    mode = "Active"
  }

  # VPC config required for Redis access
  vpc_config {
    subnet_ids         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      REDIS_SECRET_ARN = aws_secretsmanager_secret.redis_auth.arn
      REDIS_ENDPOINT   = aws_elasticache_replication_group.redis.primary_endpoint_address
      REDIS_PORT       = "6379"
      DYNAMODB_TRADES_TABLE = aws_dynamodb_table.trades.name
      TRADES_QUEUE_URL  = aws_sqs_queue.trades_queue.url
      AWS_XRAY_CONTEXT_MISSING = "LOG_ERROR"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.matcher_lambda
  ]
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "ingest_lambda" {
  name              = "/aws/lambda/ExchangeIngest"
  retention_in_days = 7  # Keep logs for 7 days to save costs
}

resource "aws_cloudwatch_log_group" "matcher_lambda" {
  name              = "/aws/lambda/ExchangeMatcher"
  retention_in_days = 7  # Keep logs for 7 days to save costs
}

# Event Source Mapping: SQS Orders Queue -> Matcher Lambda
resource "aws_lambda_event_source_mapping" "matcher_sqs" {
  event_source_arn = aws_sqs_queue.orders_queue.arn
  function_name    = aws_lambda_function.matcher.arn
  batch_size       = 10  # Process 10 messages per invocation (cost optimization)

  # Error handling with partial batch responses
  function_response_types = ["ReportBatchItemFailures"]
}
