resource "aws_dynamodb_table" "orders" {
  name         = "Orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "OrderId"
  attribute {
    name = "OrderId"
    type = "S"
  }
}

resource "aws_dynamodb_table" "trades" {
  name         = "Trades"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "TradeId"
  attribute {
    name = "TradeId"
    type = "S"
  }
}

resource "aws_sqs_queue" "orders_queue" {
  name                        = "orders.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
}

resource "aws_sqs_queue" "trades_queue" {
  name                        = "trades.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}
