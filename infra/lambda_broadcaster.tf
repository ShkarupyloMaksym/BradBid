# ============================================================================
# Broadcaster Lambda Function
# ============================================================================

# IAM Role for Broadcaster Lambda
resource "aws_iam_role" "broadcaster_lambda_role" {
  name = "${var.project_name}-broadcaster-lambda-role"

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
    Name        = "${var.project_name}-broadcaster-lambda-role"
    Environment = var.environment
  }
}

# IAM Policy for Broadcaster Lambda - SQS Trades Queue permissions
resource "aws_iam_policy" "broadcaster_lambda_sqs_policy" {
  name        = "${var.project_name}-broadcaster-lambda-sqs-policy"
  description = "Policy for Broadcaster Lambda to receive and delete messages from SQS trades queue"

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
        Resource = aws_sqs_queue.trades_fifo.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-broadcaster-lambda-sqs-policy"
    Environment = var.environment
  }
}

# IAM Policy for Broadcaster Lambda - DynamoDB WSConnections permissions
resource "aws_iam_policy" "broadcaster_lambda_dynamodb_policy" {
  name        = "${var.project_name}-broadcaster-lambda-dynamodb-policy"
  description = "Policy for Broadcaster Lambda to read/write WebSocket connections table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.ws_connections.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-broadcaster-lambda-dynamodb-policy"
    Environment = var.environment
  }
}

# IAM Policy for Broadcaster Lambda - API Gateway WebSocket permissions
resource "aws_iam_policy" "broadcaster_lambda_apigw_policy" {
  name        = "${var.project_name}-broadcaster-lambda-apigw-policy"
  description = "Policy for Broadcaster Lambda to post to WebSocket connections"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-broadcaster-lambda-apigw-policy"
    Environment = var.environment
  }
}

# Attach policies to Broadcaster Lambda role
resource "aws_iam_role_policy_attachment" "broadcaster_lambda_sqs_policy_attachment" {
  role       = aws_iam_role.broadcaster_lambda_role.name
  policy_arn = aws_iam_policy.broadcaster_lambda_sqs_policy.arn
}

resource "aws_iam_role_policy_attachment" "broadcaster_lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.broadcaster_lambda_role.name
  policy_arn = aws_iam_policy.broadcaster_lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "broadcaster_lambda_apigw_policy_attachment" {
  role       = aws_iam_role.broadcaster_lambda_role.name
  policy_arn = aws_iam_policy.broadcaster_lambda_apigw_policy.arn
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "broadcaster_lambda_basic_execution" {
  role       = aws_iam_role.broadcaster_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Archive the Lambda function code
data "archive_file" "broadcaster_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/broadcaster"
  output_path = "${path.module}/.terraform/lambda_packages/broadcaster_lambda.zip"
}

# Broadcaster Lambda Function
resource "aws_lambda_function" "broadcaster_lambda" {
  filename         = data.archive_file.broadcaster_lambda_zip.output_path
  function_name    = "${var.project_name}-broadcaster"
  role            = aws_iam_role.broadcaster_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.broadcaster_lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      WS_CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
      WEBSOCKET_API_ID     = aws_apigatewayv2_api.websocket_api.id
      WEBSOCKET_STAGE      = "dev"
    }
  }

  tags = {
    Name        = "${var.project_name}-broadcaster-lambda"
    Environment = var.environment
  }
}

# CloudWatch Log Group for Broadcaster Lambda
resource "aws_cloudwatch_log_group" "broadcaster_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.broadcaster_lambda.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-broadcaster-lambda-logs"
    Environment = var.environment
  }
}

# ============================================================================
# SQS Event Source Mapping (Trigger)
# ============================================================================

# Lambda Event Source Mapping for SQS trades.fifo queue
resource "aws_lambda_event_source_mapping" "broadcaster_sqs_trigger" {
  event_source_arn = aws_sqs_queue.trades_fifo.arn
  function_name    = aws_lambda_function.broadcaster_lambda.arn
  
  # Batch settings (batching window not supported for FIFO queues)
  batch_size = 10  # Process up to 10 trades at once
  
  # Error handling
  function_response_types = ["ReportBatchItemFailures"]
  
  # Enable the trigger
  enabled = true
}

# ============================================================================
# Outputs
# ============================================================================

output "broadcaster_lambda_arn" {
  description = "ARN of the Broadcaster Lambda function"
  value       = aws_lambda_function.broadcaster_lambda.arn
}

output "broadcaster_lambda_name" {
  description = "Name of the Broadcaster Lambda function"
  value       = aws_lambda_function.broadcaster_lambda.function_name
}

output "ws_connections_table_name" {
  description = "Name of the WebSocket Connections DynamoDB table"
  value       = aws_dynamodb_table.ws_connections.name
}
