# Bidding Exchange Service - Backend

This directory contains the Lambda functions for the Bidding Exchange Service.

## Structure

```
backend/
├── ingest/              # Ingest Lambda - validates and ingests orders
│   ├── lambda_function.py
│   ├── requirements.txt
│   └── test_lambda_function.py
├── matcher/             # Matcher Lambda - processes orders and matches trades
│   ├── lambda_function.py
│   ├── requirements.txt
│   └── test_lambda_function.py
├── requirements-dev.txt # Development dependencies
├── pytest.ini          # Pytest configuration
└── README.md
```

## Local Development

### Prerequisites

- Python 3.11+
- Docker and Docker Compose
- AWS CLI (for LocalStack)

### Setup

1. Install dependencies:
```bash
pip install -r requirements-dev.txt
```

2. Start LocalStack and Redis:
```bash
docker-compose up -d
```

3. Wait for services to be healthy:
```bash
docker-compose ps
```

### Running Tests

#### Quick Test Run
```bash
# Linux/Mac
./run_tests.sh

# Windows
run_tests.bat
```

#### Manual Test Execution

Run all unit tests:
```bash
pytest
```

Run tests with coverage:
```bash
pytest --cov=ingest --cov=matcher --cov-report=html --cov-report=term-missing
```

Run specific test file:
```bash
pytest ingest/test_lambda_function.py
pytest matcher/test_lambda_function.py
```

Run specific test class:
```bash
pytest ingest/test_lambda_function.py::TestValidateOrder
```

Run specific test:
```bash
pytest ingest/test_lambda_function.py::TestValidateOrder::test_valid_buy_order
```

Run integration tests (requires LocalStack):
```bash
pytest test_integration.py -v -m integration
```

#### Test Coverage

The test suite includes:

**Ingest Lambda Tests:**
- Order validation (valid/invalid orders)
- Missing field validation
- Numeric type validation
- Timestamp auto-generation
- Order ID auto-generation
- Partition key generation
- Error handling (Kinesis, DynamoDB failures)
- Edge cases (empty body, None values, etc.)

**Matcher Lambda Tests:**
- Order book operations (add, get, remove)
- Order matching logic (buy/sell, exact price, multiple orders)
- Partial fills
- Idempotency checks
- Trade creation and persistence
- Error handling (Redis, DynamoDB, Kinesis failures)
- Batch processing
- Orphaned entry cleanup

**Integration Tests:**
- AWS service connectivity (Kinesis, DynamoDB, S3, Secrets Manager)
- End-to-end workflows

### LocalStack Setup

LocalStack provides local AWS services for testing. After starting LocalStack:

1. Set AWS endpoint:
```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

2. Create Kinesis streams:
```bash
aws --endpoint-url=http://localhost:4566 kinesis create-stream \
  --stream-name KDS_Orders --shard-count 1

aws --endpoint-url=http://localhost:4566 kinesis create-stream \
  --stream-name KDS_Trades --shard-count 1
```

3. Create DynamoDB tables:
```bash
aws --endpoint-url=http://localhost:4566 dynamodb create-table \
  --table-name Orders \
  --attribute-definitions AttributeName=OrderId,AttributeType=S \
  --key-schema AttributeName=OrderId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

aws --endpoint-url=http://localhost:4566 dynamodb create-table \
  --table-name Trades \
  --attribute-definitions AttributeName=TradeId,AttributeType=S \
  --key-schema AttributeName=TradeId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

4. Create S3 bucket:
```bash
aws --endpoint-url=http://localhost:4566 s3 mb s3://test-data-lake
```

5. Create Secrets Manager secret for Redis:
```bash
aws --endpoint-url=http://localhost:4566 secretsmanager create-secret \
  --name redis-auth-token \
  --secret-string '{"auth_token":"testpassword"}'
```

### Testing Lambda Functions Locally

#### Ingest Lambda

```python
import json
from ingest.lambda_function import lambda_handler

event = {
    'body': json.dumps({
        'orderId': 'test-123',
        'symbol': 'BTCUSD',
        'side': 'BUY',
        'quantity': 1.5,
        'price': 50000.0
    })
}

context = {}  # Mock context
response = lambda_handler(event, context)
print(response)
```

#### Matcher Lambda

```python
import json
from matcher.lambda_function import lambda_handler

event = {
    'Records': [
        {
            'kinesis': {
                'data': json.dumps({
                    'orderId': 'test-123',
                    'symbol': 'BTCUSD',
                    'side': 'BUY',
                    'quantity': 1.5,
                    'price': 50000.0,
                    'timestamp': 1234567890
                }),
                'sequenceNumber': 'seq-123'
            }
        }
    ]
}

context = {}  # Mock context
response = lambda_handler(event, context)
print(response)
```

## Environment Variables

### Ingest Lambda
- `KINESIS_ORDERS_STREAM`: Name of the Kinesis stream for orders
- `DYNAMODB_ORDERS_TABLE`: (Optional) DynamoDB table name for orders audit

### Matcher Lambda
- `REDIS_SECRET_ARN`: ARN of the Secrets Manager secret containing Redis auth token
- `REDIS_ENDPOINT`: Redis cluster endpoint
- `REDIS_PORT`: Redis port (default: 6379)
- `DYNAMODB_TRADES_TABLE`: DynamoDB table name for trades
- `KINESIS_TRADES_STREAM`: Kinesis stream name for trade events

## Order Format

```json
{
  "orderId": "string (optional, auto-generated if not provided)",
  "symbol": "string (e.g., BTCUSD)",
  "side": "BUY | SELL",
  "quantity": number (must be positive),
  "price": number (must be positive),
  "timestamp": number (optional, milliseconds since epoch)"
}
```

## Trade Format

```json
{
  "tradeId": "string (UUID)",
  "symbol": "string",
  "buyOrderId": "string",
  "sellOrderId": "string",
  "price": number,
  "quantity": number,
  "timestamp": number (milliseconds since epoch)
}
```

