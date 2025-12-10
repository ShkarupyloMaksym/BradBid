"""
Pytest configuration and shared fixtures
"""
import pytest
import json
from unittest.mock import Mock, MagicMock


@pytest.fixture
def sample_buy_order():
    """Sample buy order for testing"""
    return {
        'orderId': 'test-buy-123',
        'symbol': 'BTCUSD',
        'side': 'BUY',
        'quantity': 1.5,
        'price': 50000.0,
        'timestamp': 1234567890000
    }


@pytest.fixture
def sample_sell_order():
    """Sample sell order for testing"""
    return {
        'orderId': 'test-sell-456',
        'symbol': 'BTCUSD',
        'side': 'SELL',
        'quantity': 2.0,
        'price': 51000.0,
        'timestamp': 1234567891000
    }


@pytest.fixture
def sample_trade():
    """Sample trade for testing"""
    return {
        'tradeId': 'trade-789',
        'symbol': 'BTCUSD',
        'buyOrderId': 'test-buy-123',
        'sellOrderId': 'test-sell-456',
        'price': 50000.0,
        'quantity': 1.5,
        'timestamp': 1234567892000
    }


@pytest.fixture
def mock_redis_client():
    """Mock Redis client"""
    redis = MagicMock()
    redis.exists.return_value = False
    redis.setex.return_value = True
    redis.zrange.return_value = []
    redis.hgetall.return_value = {}
    redis.zadd.return_value = True
    redis.hset.return_value = True
    redis.expire.return_value = True
    redis.zrem.return_value = True
    redis.delete.return_value = True
    redis.ping.return_value = True
    return redis


@pytest.fixture
def api_gateway_event():
    """Sample API Gateway event"""
    return {
        'body': json.dumps({
            'orderId': 'test-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'quantity': 1.5,
            'price': 50000.0
        }),
        'headers': {
            'Content-Type': 'application/json'
        },
        'requestContext': {
            'requestId': 'test-request-id'
        }
    }


@pytest.fixture
def kinesis_event():
    """Sample Kinesis event"""
    return {
        'Records': [
            {
                'kinesis': {
                    'data': json.dumps({
                        'orderId': 'test-123',
                        'symbol': 'BTCUSD',
                        'side': 'BUY',
                        'quantity': 1.5,
                        'price': 50000.0,
                        'timestamp': 1234567890000
                    }),
                    'sequenceNumber': 'seq-123',
                    'partitionKey': 'BTCUSD-BUY',
                    'approximateArrivalTimestamp': 1234567890.0
                },
                'eventSource': 'aws:kinesis',
                'eventVersion': '1.0'
            }
        ]
    }


@pytest.fixture
def lambda_context():
    """Sample Lambda context"""
    context = Mock()
    context.function_name = 'test-function'
    context.function_version = '$LATEST'
    context.invoked_function_arn = 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
    context.memory_limit_in_mb = 256
    context.aws_request_id = 'test-request-id'
    return context

