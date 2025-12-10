"""
Unit tests for Ingest Lambda Function
"""
import json
import os
import pytest
from unittest.mock import Mock, patch, MagicMock
from lambda_function import lambda_handler, validate_order


class TestValidateOrder:
    """Test order validation logic"""
    
    def test_valid_buy_order(self):
        order = {
            "orderId": "test-123",
            "symbol": "BTCUSD",
            "side": "BUY",
            "quantity": 1.5,
            "price": 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is True
        assert message == "OK"
    
    def test_valid_sell_order(self):
        order = {
            "orderId": "test-456",
            "symbol": "ETHUSD",
            "side": "SELL",
            "quantity": 2.0,
            "price": 3000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is True
    
    def test_missing_required_field(self):
        order = {
            "orderId": "test-123",
            "symbol": "BTCUSD",
            "side": "BUY",
            "quantity": 1.5
            # Missing price
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert "price" in message
    
    def test_invalid_side(self):
        order = {
            "orderId": "test-123",
            "symbol": "BTCUSD",
            "side": "INVALID",
            "quantity": 1.5,
            "price": 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert "BUY" in message or "SELL" in message
    
    def test_negative_quantity(self):
        order = {
            "orderId": "test-123",
            "symbol": "BTCUSD",
            "side": "BUY",
            "quantity": -1.5,
            "price": 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert "positive" in message.lower()
    
    def test_zero_price(self):
        order = {
            "orderId": "test-123",
            "symbol": "BTCUSD",
            "side": "BUY",
            "quantity": 1.5,
            "price": 0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert "positive" in message.lower()
    
    def test_empty_symbol(self):
        order = {
            "orderId": "test-123",
            "symbol": "",
            "side": "BUY",
            "quantity": 1.5,
            "price": 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False


class TestLambdaHandler:
    """Test Lambda handler"""
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.dynamodb_client')
    def test_successful_order_ingestion(self, mock_dynamodb, mock_kinesis):
        """Test successful order ingestion"""
        # Mock Kinesis response
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        
        # Mock DynamoDB response
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert body['message'] == 'Order accepted'
        assert 'orderId' in body
        assert 'sequenceNumber' in body
        
        # Verify Kinesis was called
        mock_kinesis.put_record.assert_called_once()
        call_args = mock_kinesis.put_record.call_args
        assert call_args[1]['StreamName'] == 'test-stream'
        
        # Verify DynamoDB was called
        mock_dynamodb.put_item.assert_called_once()
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': ''
    })
    @patch('lambda_function.kinesis_client')
    def test_order_ingestion_without_dynamodb(self, mock_kinesis):
        """Test order ingestion when DynamoDB table is not configured"""
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    def test_invalid_order_validation(self):
        """Test rejection of invalid order"""
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'INVALID',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert 'error' in body
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    def test_invalid_json(self):
        """Test handling of invalid JSON"""
        event = {
            'body': 'invalid json{'
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert 'error' in body
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    def test_kinesis_error_handling(self, mock_kinesis):
        """Test error handling when Kinesis fails"""
        mock_kinesis.put_record.side_effect = Exception("Kinesis error")
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 500
        body = json.loads(response['body'])
        assert 'error' in body
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.dynamodb_client')
    def test_auto_generate_order_id(self, mock_dynamodb, mock_kinesis):
        """Test automatic order ID generation"""
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'body': json.dumps({
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
                # No orderId
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        body = json.loads(response['body'])
        assert 'orderId' in body
        assert body['orderId']  # Should be generated
    
    def test_missing_all_required_fields(self):
        """Test validation with multiple missing fields"""
        order = {
            'orderId': 'test-123'
            # Missing symbol, side, quantity, price
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert 'Missing required field' in message
    
    def test_invalid_numeric_types(self):
        """Test validation with invalid numeric types"""
        order = {
            'orderId': 'test-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'quantity': 'not-a-number',
            'price': 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
        assert 'numeric' in message.lower()
    
    def test_whitespace_symbol(self):
        """Test validation with whitespace-only symbol"""
        order = {
            'orderId': 'test-123',
            'symbol': '   ',
            'side': 'BUY',
            'quantity': 1.5,
            'price': 50000.0
        }
        is_valid, message = validate_order(order)
        assert is_valid is False
    
    def test_very_large_numbers(self):
        """Test validation with very large numbers"""
        order = {
            'orderId': 'test-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'quantity': 1e10,
            'price': 1e10
        }
        is_valid, message = validate_order(order)
        assert is_valid is True  # Should accept large numbers
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.dynamodb_client')
    def test_timestamp_auto_generation(self, mock_dynamodb, mock_kinesis):
        """Test automatic timestamp generation"""
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
                # No timestamp
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        assert response['statusCode'] == 200
        # Verify timestamp was added to DynamoDB item
        call_args = mock_dynamodb.put_item.call_args
        assert 'Timestamp' in call_args[1]['Item']
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.dynamodb_client')
    def test_partition_key_generation(self, mock_dynamodb, mock_kinesis):
        """Test partition key is correctly generated"""
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        mock_dynamodb.put_item.return_value = {}
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        # Verify partition key format
        call_args = mock_kinesis.put_record.call_args
        partition_key = call_args[1]['PartitionKey']
        assert 'BTCUSD' in partition_key
        assert 'BUY' in partition_key
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    @patch('lambda_function.kinesis_client')
    @patch('lambda_function.dynamodb_client')
    def test_dynamodb_error_does_not_fail_request(self, mock_dynamodb, mock_kinesis):
        """Test that DynamoDB errors don't fail the request"""
        mock_kinesis.put_record.return_value = {
            'SequenceNumber': 'test-seq-123'
        }
        mock_dynamodb.put_item.side_effect = Exception("DynamoDB error")
        
        event = {
            'body': json.dumps({
                'orderId': 'test-123',
                'symbol': 'BTCUSD',
                'side': 'BUY',
                'quantity': 1.5,
                'price': 50000.0
            })
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        
        # Should still succeed even if DynamoDB fails
        assert response['statusCode'] == 200
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    def test_event_without_body(self):
        """Test handling event without body (direct invocation)"""
        event = {
            'orderId': 'test-123',
            'symbol': 'BTCUSD',
            'side': 'BUY',
            'quantity': 1.5,
            'price': 50000.0
        }
        
        context = Mock()
        
        # Should handle both API Gateway and direct invocation formats
        with patch('lambda_function.kinesis_client') as mock_kinesis:
            mock_kinesis.put_record.return_value = {
                'SequenceNumber': 'test-seq-123'
            }
            with patch('lambda_function.dynamodb_client') as mock_dynamodb:
                mock_dynamodb.put_item.return_value = {}
                
                response = lambda_handler(event, context)
                assert response['statusCode'] == 200
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    def test_empty_body(self):
        """Test handling of empty body"""
        event = {
            'body': ''
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        assert response['statusCode'] == 400
    
    @patch.dict(os.environ, {
        'KINESIS_ORDERS_STREAM': 'test-stream',
        'DYNAMODB_ORDERS_TABLE': 'test-table'
    })
    def test_none_body(self):
        """Test handling of None body"""
        event = {
            'body': None
        }
        
        context = Mock()
        
        response = lambda_handler(event, context)
        assert response['statusCode'] in [400, 500]  # Should handle gracefully

