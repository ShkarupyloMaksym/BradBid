# =============================================================================
# API GATEWAY
# Cost: Free tier: 1M requests/month, then $3.50 per million
# =============================================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "exchange_api" {
  name        = "exchange-api"
  description = "API Gateway for Bidding Exchange Service"

  endpoint_configuration {
    types = ["REGIONAL"]  # Regional is cheaper than Edge
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.exchange_api.id
  parent_id   = aws_api_gateway_rest_api.exchange_api.root_resource_id
  path_part   = "orders"
}

# POST method for orders
resource "aws_api_gateway_method" "post_orders" {
  rest_api_id   = aws_api_gateway_rest_api.exchange_api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"  # For MVP, can add API key/auth later
}

# Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.exchange_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ingest.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.exchange_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "exchange_api" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.exchange_api.id
  stage_name  = "prod"
}

# Output
output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_deployment.exchange_api.invoke_url}/orders"
}

