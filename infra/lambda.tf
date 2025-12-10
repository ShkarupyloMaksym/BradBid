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
      REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT = "6379"
      DYNAMO_TABLE = aws_dynamodb_table.trades.name
      TRADES_QUEUE_URL = aws_sqs_queue.trades_queue.url
    }
  }
}
