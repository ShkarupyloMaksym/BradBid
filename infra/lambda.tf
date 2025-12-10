data "archive_file" "dummy_zip" {
  type        = "zip"
  output_path = "${path.module}/dummy_payload.zip"
  
  source {
    content  = "def lambda_handler(event, context): return 'Hello from Terraform'"
    filename = "lambda_function.py"
  }
}

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

resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_lambda_function" "ingest" {
  filename         = data.archive_file.dummy_zip.output_path
  function_name    = "ExchangeIngest"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      ORDERS_QUEUE_URL = aws_sqs_queue.orders_queue.url
    }
  }
}

resource "aws_lambda_function" "matcher" {
  filename         = data.archive_file.dummy_zip.output_path
  function_name    = "ExchangeMatcher"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256
  timeout          = 30 

  vpc_config {
    subnet_ids         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      REDIS_HOST       = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT       = "6379"
      DYNAMO_TABLE     = aws_dynamodb_table.trades.name
      TRADES_QUEUE_URL = aws_sqs_queue.trades_queue.url
      FIREHOSE_STREAM  = aws_kinesis_firehose_delivery_stream.trades_firehose.name
    }
  }
}

# SQS Trigger for Matcher Lambda (Krок 7)
resource "aws_lambda_event_source_mapping" "orders_sqs_trigger" {
  event_source_arn = aws_sqs_queue.orders_queue.arn
  function_name    = aws_lambda_function.matcher.arn
  batch_size       = 1  # For MVP, process one order at a time
  enabled          = true
}

# =============================================================================
# WebSocket Handler Lambda (Krок 8)
# Handles WebSocket connections and subscriptions
# =============================================================================
resource "aws_lambda_function" "ws_handler" {
  filename         = data.archive_file.dummy_zip.output_path
  function_name    = "ExchangeWSHandler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
    }
  }
}

# DynamoDB table for WebSocket connections
resource "aws_dynamodb_table" "ws_connections" {
  name         = "WSConnections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ConnectionId"
  
  attribute {
    name = "ConnectionId"
    type = "S"
  }

  ttl {
    attribute_name = "TTL"
    enabled        = true
  }
}

# =============================================================================
# Trade Broadcaster Lambda (Krок 8)
# Listens to trades.fifo and broadcasts updates to WebSocket clients
# =============================================================================
resource "aws_lambda_function" "trade_broadcaster" {
  filename         = data.archive_file.dummy_zip.output_path
  function_name    = "ExchangeTradeBroadcaster"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.dummy_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      CONNECTIONS_TABLE = aws_dynamodb_table.ws_connections.name
      WEBSOCKET_API_ENDPOINT = "https://${aws_apigatewayv2_api.websocket_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_apigatewayv2_stage.websocket_stage.name}"
    }
  }
}

# SQS Trigger for Trade Broadcaster Lambda
resource "aws_lambda_event_source_mapping" "trades_sqs_trigger" {
  event_source_arn = aws_sqs_queue.trades_queue.arn
  function_name    = aws_lambda_function.trade_broadcaster.arn
  batch_size       = 10
  enabled          = true
}
