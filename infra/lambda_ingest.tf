# ============================================================================
# Ingest Lambda Function
# ============================================================================

# IAM Role for Ingest Lambda
resource "aws_iam_role" "ingest_lambda_role" {
  name = "${var.project_name}-ingest-lambda-role"

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
    Name        = "${var.project_name}-ingest-lambda-role"
    Environment = var.environment
  }
}

# IAM Policy for Ingest Lambda - SQS permissions
resource "aws_iam_policy" "ingest_lambda_sqs_policy" {
  name        = "${var.project_name}-ingest-lambda-sqs-policy"
  description = "Policy for Ingest Lambda to send messages to SQS"

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
        Resource = aws_sqs_queue.orders_fifo.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ingest-lambda-sqs-policy"
    Environment = var.environment
  }
}

# Attach SQS policy to Lambda role
resource "aws_iam_role_policy_attachment" "ingest_lambda_sqs_policy_attachment" {
  role       = aws_iam_role.ingest_lambda_role.name
  policy_arn = aws_iam_policy.ingest_lambda_sqs_policy.arn
}

# Attach AWS managed policy for basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "ingest_lambda_basic_execution" {
  role       = aws_iam_role.ingest_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Archive the Lambda function code
data "archive_file" "ingest_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/ingest"
  output_path = "${path.module}/.terraform/lambda_packages/ingest_lambda.zip"
}

# Ingest Lambda Function
resource "aws_lambda_function" "ingest_lambda" {
  filename         = data.archive_file.ingest_lambda_zip.output_path
  function_name    = "${var.project_name}-ingest"
  role            = aws_iam_role.ingest_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.ingest_lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.orders_fifo.url
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-ingest-lambda"
    Environment = var.environment
  }
}

# CloudWatch Log Group for Ingest Lambda
resource "aws_cloudwatch_log_group" "ingest_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ingest_lambda.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-ingest-lambda-logs"
    Environment = var.environment
  }
}

# ============================================================================
# API Gateway Integration for Ingest Lambda
# ============================================================================

# Lambda Integration for POST /orders
resource "aws_apigatewayv2_integration" "orders_lambda" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ingest_lambda.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# Update Route: POST /orders with integration
resource "aws_apigatewayv2_route" "post_orders_with_integration" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /orders"
  
  # TEMPORARILY DISABLED FOR TESTING - Re-enable Cognito authorization later
  authorization_type = "NONE"
  # authorizer_id      = aws_apigatewayv2_authorizer.cognito.id

  target = "integrations/${aws_apigatewayv2_integration.orders_lambda.id}"
}

# Lambda permission for API Gateway to invoke Ingest Lambda
resource "aws_lambda_permission" "api_gateway_ingest" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*/orders"
}

# ============================================================================
# Outputs
# ============================================================================

output "ingest_lambda_arn" {
  description = "ARN of the Ingest Lambda function"
  value       = aws_lambda_function.ingest_lambda.arn
}

output "ingest_lambda_name" {
  description = "Name of the Ingest Lambda function"
  value       = aws_lambda_function.ingest_lambda.function_name
}
