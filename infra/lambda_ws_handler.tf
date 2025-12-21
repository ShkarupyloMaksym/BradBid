# ============================================================================
# WebSocket Handler Lambda Function
# ============================================================================

# IAM Role for WebSocket Handler Lambda
resource "aws_iam_role" "ws_handler_lambda_role" {
  name = "${var.project_name}-ws-handler-lambda-role"

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
    Name        = "${var.project_name}-ws-handler-lambda-role"
    Environment = var.environment
  }
}

# IAM Policy for WebSocket Handler Lambda - DynamoDB WSConnections permissions
resource "aws_iam_policy" "ws_handler_lambda_dynamodb_policy" {
  name        = "${var.project_name}-ws-handler-lambda-dynamodb-policy"
  description = "Policy for WebSocket Handler Lambda to manage connections in DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.ws_connections.arn
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ws-handler-lambda-dynamodb-policy"
    Environment = var.environment
  }
}

# Attach policies to WebSocket Handler Lambda role
resource "aws_iam_role_policy_attachment" "ws_handler_lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.ws_handler_lambda_role.name
  policy_arn = aws_iam_policy.ws_handler_lambda_dynamodb_policy.arn
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "ws_handler_lambda_basic_execution" {
  role       = aws_iam_role.ws_handler_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Archive the Lambda function code
data "archive_file" "ws_handler_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/ws_handler"
  output_path = "${path.module}/.terraform/lambda_packages/ws_handler_lambda.zip"
}

# WebSocket Handler Lambda Function
resource "aws_lambda_function" "ws_handler_lambda" {
  filename         = data.archive_file.ws_handler_lambda_zip.output_path
  function_name    = "${var.project_name}-ws-handler"
  role            = aws_iam_role.ws_handler_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.ws_handler_lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      WS_CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
      ENVIRONMENT          = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-ws-handler-lambda"
    Environment = var.environment
  }
}

# CloudWatch Log Group for WebSocket Handler Lambda
resource "aws_cloudwatch_log_group" "ws_handler_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ws_handler_lambda.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-ws-handler-lambda-logs"
    Environment = var.environment
  }
}

# ============================================================================
# WebSocket API Integration
# ============================================================================

# Lambda Integration for WebSocket API
resource "aws_apigatewayv2_integration" "ws_handler" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ws_handler_lambda.invoke_arn
}

# Update WebSocket Routes with Integration
resource "aws_apigatewayv2_route" "ws_connect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

resource "aws_apigatewayv2_route" "ws_default" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.ws_handler.id}"
}

# Lambda permissions for WebSocket API
resource "aws_lambda_permission" "ws_handler_connect" {
  statement_id  = "AllowAPIGatewayInvokeConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_handler_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/$connect"
}

resource "aws_lambda_permission" "ws_handler_disconnect" {
  statement_id  = "AllowAPIGatewayInvokeDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_handler_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/$disconnect"
}

resource "aws_lambda_permission" "ws_handler_default" {
  statement_id  = "AllowAPIGatewayInvokeDefault"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_handler_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/$default"
}

# ============================================================================
# Outputs
# ============================================================================

output "ws_handler_lambda_arn" {
  description = "ARN of the WebSocket Handler Lambda function"
  value       = aws_lambda_function.ws_handler_lambda.arn
}

output "ws_handler_lambda_name" {
  description = "Name of the WebSocket Handler Lambda function"
  value       = aws_lambda_function.ws_handler_lambda.function_name
}
