"""
Unit tests for Matcher Lambda Function
"""
import json
import os
import pytest
from unittest.mock import Mock, patch, MagicMock
from lambda_function import (
    lambda_handler,
    match_orders,
    get_best_order,
    add_order_to_book,
    remove_order_from_book
)


class TestOrderBookOperations:
    """Test order book operations"""
    
    @patch('lambda_function.get_redis_client')
    def test_add_order_to_book(self, mock_get_redis):
        """Test adding order to order book"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        order = {
            'orderId': 'order-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 50000.0,
            'quantity': 1.5,
            'timestamp': 1234567890
        }
        
        from lambda_function import add_order_to_book
        add_order_to_book(mock_redis, order)
        
        # Verify Redis operations
        assert mock_redis.zadd.called
        assert mock_redis.hset.called
        assert mock_redis.expire.called
    
    @patch('lambda_function.get_redis_client')
    def test_get_best_order(self, mock_get_redis):
        """Test getting best order from order book"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock Redis responses
        mock_redis.zrange.return_value = ['order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'order-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': '50000.0',
            'quantity': '1.5',
            'timestamp': '1234567890'
        }
        
        from lambda_function import get_best_order
        result = get_best_order(mock_redis, 'BTCUSD', 'BUY')
        
        assert result is not None
        assert result['orderId'] == 'order-123'
        assert result['price'] == '50000.0'
    
    @patch('lambda_function.get_redis_client')
    def test_get_best_order_empty_book(self, mock_get_redis):
        """Test getting best order when order book is empty"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        mock_redis.zrange.return_value = []
        
        from lambda_function import get_best_order
        result = get_best_order(mock_redis, 'BTCUSD', 'BUY')
        
        assert result is None


class TestOrderMatching:
    """Test order matching logic"""
    
    @patch('lambda_function.get_redis_client')
    def test_match_buy_order_with_sell_order(self, mock_get_redis):
        """Test matching a buy order with existing sell order"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock idempotency check
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order (sell order)
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 51000.0,  # Higher than sell price - should match
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should create a trade
        assert len(trades) > 0
        trade = trades[0]
        assert trade['symbol'] == 'BTCUSD'
        assert trade['price'] == 50000.0  # Match at sell order price
        assert trade['quantity'] == 1.5
    
    @patch('lambda_function.get_redis_client')
    def test_match_partial_fill(self, mock_get_redis):
        """Test partial order fill"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock idempotency check
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order with smaller quantity
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '1.0',  # Less than buy order quantity
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 51000.0,
            'quantity': 2.0,  # More than sell order
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should create a trade for 1.0
        assert len(trades) > 0
        assert trades[0]['quantity'] == 1.0
        
        # Remaining order should be added to book
        assert mock_redis.zadd.called  # Should add remaining to book
    
    @patch('lambda_function.get_redis_client')
    def test_no_match_price_too_low(self, mock_get_redis):
        """Test no match when buy price is too low"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock idempotency check
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order (sell order with higher price)
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 49000.0,  # Lower than sell price - no match
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should not create trades, order should be added to book
        assert len(trades) == 0
        assert mock_redis.zadd.called  # Should add to book
    
    @patch('lambda_function.get_redis_client')
    def test_idempotency_check(self, mock_get_redis):
        """Test idempotency - same order processed twice"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock idempotency check - order already processed
        mock_redis.exists.return_value = True
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 50000.0,
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should return empty trades (already processed)
        assert len(trades) == 0
        # Should not try to match
        assert not mock_redis.zrange.called


class TestLambdaHandler:
    """Test Lambda handler"""
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.dynamodb_client')
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.secrets_client')
    def test_successful_order_processing(self, mock_secrets, mock_kinesis, mock_dynamodb, mock_get_redis):
        """Test successful order processing"""
        # Mock Redis
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        mock_redis.zrange.return_value = []
        
        # Mock Secrets Manager
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        # Mock Kinesis
        mock_kinesis.put_record.return_value = {'SequenceNumber': 'test-seq'}
        
        # Mock DynamoDB
        mock_dynamodb.put_item.return_value = {}
        
        # Kinesis event
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
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        assert 'tradesProcessed' in response
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.secrets_client')
    def test_batch_item_failures(self, mock_secrets, mock_get_redis):
        """Test handling of batch item failures"""
        # Mock Redis to raise error
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        mock_redis.exists.side_effect = Exception("Redis error")
        
        # Mock Secrets Manager
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-123',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.5,
                            'price': 50000.0
                        }),
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        # Should return batch item failures
        assert 'batchItemFailures' in response
        assert len(response['batchItemFailures']) > 0
    
    @patch('lambda_function.get_redis_client')
    def test_match_exact_price(self, mock_get_redis):
        """Test matching when prices are exactly equal"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order with exact same price
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 50000.0,  # Exact match
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should match at exact price
        assert len(trades) > 0
        assert trades[0]['price'] == 50000.0
    
    @patch('lambda_function.get_redis_client')
    def test_match_multiple_orders(self, mock_get_redis):
        """Test matching against multiple orders in sequence"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # First order (fully consumed)
        order1 = {
            'orderId': 'sell-order-1',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '1.0',
            'timestamp': '1234567890'
        }
        
        # Second order (partially consumed)
        order2 = {
            'orderId': 'sell-order-2',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50100.0',
            'quantity': '2.0',
            'timestamp': '1234567891'
        }
        
        # Mock sequence: first call returns order1, second call returns order2
        mock_redis.zrange.side_effect = [['sell-order-1'], ['sell-order-2']]
        mock_redis.hgetall.side_effect = [order1, order2]
        
        new_order = {
            'orderId': 'buy-order-456',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': 51000.0,  # Higher than both
            'quantity': 2.5,  # More than first, less than first+second
            'timestamp': 1234567892
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should create multiple trades
        assert len(trades) >= 1
        # First trade should be at 50000.0
        assert trades[0]['price'] == 50000.0
    
    @patch('lambda_function.get_redis_client')
    def test_match_sell_order_with_buy_order(self, mock_get_redis):
        """Test matching a sell order with existing buy order"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order (buy order)
        mock_redis.zrange.return_value = ['buy-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'buy-order-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': '51000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'sell-order-456',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': 50000.0,  # Lower than buy price - should match
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should create a trade
        assert len(trades) > 0
        trade = trades[0]
        assert trade['price'] == 51000.0  # Match at buy order price
        assert trade['sellOrderId'] == 'sell-order-456'
        assert trade['buyOrderId'] == 'buy-order-123'
    
    @patch('lambda_function.get_redis_client')
    def test_no_match_price_too_high_sell(self, mock_get_redis):
        """Test no match when sell price is too high"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        
        # Mock best order (buy order with lower price)
        mock_redis.zrange.return_value = ['buy-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'buy-order-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        new_order = {
            'orderId': 'sell-order-456',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': 51000.0,  # Higher than buy price - no match
            'quantity': 1.5,
            'timestamp': 1234567891
        }
        
        trades = match_orders(mock_redis, new_order)
        
        # Should not create trades
        assert len(trades) == 0
        assert mock_redis.zadd.called  # Should add to book
    
    @patch('lambda_function.get_redis_client')
    def test_remove_order_from_book(self, mock_get_redis):
        """Test removing order from order book"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        from lambda_function import remove_order_from_book
        remove_order_from_book(mock_redis, 'order-123', 'BTCUSD', 'BUY')
        
        # Verify Redis operations
        assert mock_redis.zrem.called
        assert mock_redis.delete.called
    
    @patch('lambda_function.get_redis_client')
    def test_update_order_quantity(self, mock_get_redis):
        """Test updating order quantity"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        from lambda_function import update_order_quantity
        update_order_quantity(mock_redis, 'order-123', 0.5)
        
        # Verify Redis operation
        assert mock_redis.hset.called
        call_args = mock_redis.hset.call_args
        assert call_args[0][0] == 'order:order-123'
        assert call_args[0][1] == 'quantity'
        assert call_args[0][2] == '0.5'
    
    @patch('lambda_function.get_redis_client')
    def test_get_best_order_orphaned_entry(self, mock_get_redis):
        """Test handling orphaned order book entry"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        
        # Mock Redis: order exists in sorted set but not in hash
        mock_redis.zrange.return_value = ['order-123']
        mock_redis.hgetall.return_value = {}  # Empty hash
        
        from lambda_function import get_best_order
        result = get_best_order(mock_redis, 'BTCUSD', 'BUY')
        
        # Should return None and clean up
        assert result is None
        assert mock_redis.zrem.called  # Should remove orphaned entry
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.dynamodb_client')
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.secrets_client')
    def test_multiple_records_processing(self, mock_secrets, mock_kinesis, mock_dynamodb, mock_get_redis):
        """Test processing multiple Kinesis records"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        mock_redis.zrange.return_value = []
        
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        mock_kinesis.put_record.return_value = {'SequenceNumber': 'test-seq'}
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-1',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.0,
                            'price': 50000.0,
                            'timestamp': 1234567890
                        }),
                        'sequenceNumber': 'seq-1'
                    }
                },
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-2',
                            'symbol': 'ETHUSD',
                            'side': 'SELL',
                            'quantity': 2.0,
                            'price': 3000.0,
                            'timestamp': 1234567891
                        }),
                        'sequenceNumber': 'seq-2'
                    }
                }
            ]
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        # Should process both records
        assert mock_redis.exists.call_count == 2
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.dynamodb_client')
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.secrets_client')
    def test_dynamodb_failure_handling(self, mock_secrets, mock_kinesis, mock_dynamodb, mock_get_redis):
        """Test handling of DynamoDB failures"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        mock_kinesis.put_record.return_value = {'SequenceNumber': 'test-seq'}
        mock_dynamodb.put_item.side_effect = Exception("DynamoDB error")
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-123',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.5,
                            'price': 51000.0,
                            'timestamp': 1234567890
                        }),
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        # Should raise exception (fail the batch item)
        with pytest.raises(Exception):
            lambda_handler(event, context)
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.dynamodb_client')
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.secrets_client')
    def test_kinesis_failure_handling(self, mock_secrets, mock_kinesis, mock_dynamodb, mock_get_redis):
        """Test handling of Kinesis failures"""
        mock_redis = MagicMock()
        mock_get_redis.return_value = mock_redis
        mock_redis.exists.return_value = False
        mock_redis.setex.return_value = True
        mock_redis.zrange.return_value = ['sell-order-123']
        mock_redis.hgetall.return_value = {
            'orderId': 'sell-order-123',
            'symbol': 'BTCUSD',
            'side': 'SELL',
            'price': '50000.0',
            'quantity': '2.0',
            'timestamp': '1234567890'
        }
        
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        mock_kinesis.put_record.side_effect = Exception("Kinesis error")
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-123',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.5,
                            'price': 51000.0,
                            'timestamp': 1234567890
                        }),
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        # Should raise exception (fail the batch item)
        with pytest.raises(Exception):
            lambda_handler(event, context)
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.secrets_client')
    def test_redis_connection_failure(self, mock_secrets, mock_get_redis):
        """Test handling of Redis connection failure"""
        mock_secrets.get_secret_value.return_value = {
            'SecretString': json.dumps({'auth_token': 'test-token'})
        }
        
        # Mock Redis connection failure
        mock_get_redis.side_effect = Exception("Redis connection failed")
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-123',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.5,
                            'price': 50000.0
                        }),
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        # Should raise exception
        with pytest.raises(Exception):
            lambda_handler(event, context)
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    @patch('lambda_function.get_redis_client')
    @patch('lambda_function.secrets_client')
    def test_secrets_manager_failure(self, mock_secrets, mock_get_redis):
        """Test handling of Secrets Manager failure"""
        mock_secrets.get_secret_value.side_effect = Exception("Secrets Manager error")
        
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': json.dumps({
                            'orderId': 'test-123',
                            'symbol': 'BTCUSD',
                            'side': 'BUY',
                            'quantity': 1.5,
                            'price': 50000.0
                        }),
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        # Should raise exception
        with pytest.raises(Exception):
            lambda_handler(event, context)
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    def test_empty_records(self):
        """Test handling of empty records"""
        event = {
            'Records': []
        }
        
        context = Mock()
        
        with patch('lambda_function.get_redis_client') as mock_get_redis:
            mock_redis = MagicMock()
            mock_get_redis.return_value = mock_redis
            
            response = lambda_handler(event, context)
            
            assert response['statusCode'] == 200
            assert response.get('tradesProcessed', 0) == 0
    
    @patch.dict(os.environ, {
        'REDIS_SECRET_ARN': 'arn:aws:secretsmanager:us-east-1:123456789012:secret:test',
        'REDIS_ENDPOINT': 'localhost',
        'REDIS_PORT': '6379',
        'DYNAMODB_TRADES_TABLE': 'test-trades',
        'KINESIS_TRADES_STREAM': 'test-trades-stream'
    })
    def test_invalid_json_in_record(self):
        """Test handling of invalid JSON in Kinesis record"""
        event = {
            'Records': [
                {
                    'kinesis': {
                        'data': 'invalid json{',
                        'sequenceNumber': 'seq-123'
                    }
                }
            ]
        }
        
        context = Mock()
        
        with patch('lambda_function.get_redis_client') as mock_get_redis:
            mock_redis = MagicMock()
            mock_get_redis.return_value = mock_redis
            mock_redis.exists.return_value = False
            
            response = lambda_handler(event, context)
            
            # Should return batch item failures
            assert 'batchItemFailures' in response

