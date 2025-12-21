# ============================================================================
# Network Outputs
# ============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "lambda_sg_id" {
  description = "Lambda security group ID"
  value       = aws_security_group.lambda_sg.id
}

output "redis_sg_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis_sg.id
}

# ============================================================================
# Database Outputs
# ============================================================================

output "orders_table_name" {
  description = "Orders DynamoDB table name"
  value       = aws_dynamodb_table.orders.name
}

output "trades_table_name" {
  description = "Trades DynamoDB table name"
  value       = aws_dynamodb_table.trades.name
}

# ============================================================================
# Queue Outputs
# ============================================================================

output "orders_queue_url" {
  description = "Orders SQS FIFO queue URL"
  value       = aws_sqs_queue.orders_fifo.url
}

output "trades_queue_url" {
  description = "Trades SQS FIFO queue URL"
  value       = aws_sqs_queue.trades_fifo.url
}

# ============================================================================
# Cache Outputs
# ============================================================================

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.redis.port
}

# ============================================================================
# Authentication Outputs
# ============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.exchange_users.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.exchange_users.arn
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.web_client.id
}

output "cognito_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "http_api_url" {
  description = "HTTP API Gateway URL"
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/${var.environment}"
}

output "http_api_id" {
  description = "HTTP API Gateway ID"
  value       = aws_apigatewayv2_api.http_api.id
}

output "websocket_api_url" {
  description = "WebSocket API Gateway URL"
  value       = "${aws_apigatewayv2_api.websocket_api.api_endpoint}/${var.environment}"
}

output "websocket_api_id" {
  description = "WebSocket API Gateway ID"
  value       = aws_apigatewayv2_api.websocket_api.id
}
