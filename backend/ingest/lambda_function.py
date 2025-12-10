"""
Ingest Lambda (Krок 7)
Handles POST /orders requests from API Gateway
Validates order JSON and sends to SQS orders.fifo queue
"""
import json
import os
import uuid
from datetime import datetime

# Lazy initialization of boto3 client
_sqs_client = None

def get_sqs_client():
    """Get or create SQS client (lazy initialization for testability)."""
    global _sqs_client
    if _sqs_client is None:
        import boto3
        _sqs_client = boto3.client('sqs')
    return _sqs_client

ORDERS_QUEUE_URL = os.environ.get('ORDERS_QUEUE_URL')

# Order schema validation
REQUIRED_FIELDS = ['symbol', 'side', 'order_type', 'quantity']
VALID_SIDES = ['buy', 'sell']
VALID_ORDER_TYPES = ['market', 'limit']


def validate_order(order: dict) -> tuple[bool, str]:
    """Validate order JSON structure and values."""
    # Check required fields
    for field in REQUIRED_FIELDS:
        if field not in order:
            return False, f"Missing required field: {field}"
    
    # Validate side
    if order['side'].lower() not in VALID_SIDES:
        return False, f"Invalid side: {order['side']}. Must be 'buy' or 'sell'"
    
    # Validate order type
    if order['order_type'].lower() not in VALID_ORDER_TYPES:
        return False, f"Invalid order_type: {order['order_type']}. Must be 'market' or 'limit'"
    
    # Validate quantity
    try:
        quantity = float(order['quantity'])
        if quantity <= 0:
            return False, "Quantity must be greater than 0"
    except (ValueError, TypeError):
        return False, "Invalid quantity: must be a positive number"
    
    # For limit orders, price is required
    if order['order_type'].lower() == 'limit':
        if 'price' not in order:
            return False, "Price is required for limit orders"
        try:
            price = float(order['price'])
            if price <= 0:
                return False, "Price must be greater than 0"
        except (ValueError, TypeError):
            return False, "Invalid price: must be a positive number"
    
    return True, ""


def lambda_handler(event, context):
    """
    Handle incoming order requests from API Gateway.
    
    Expected event structure (API Gateway HTTP API v2):
    {
        "body": "{\"symbol\": \"BTC-USD\", \"side\": \"buy\", \"order_type\": \"limit\", \"quantity\": 1.0, \"price\": 50000}",
        "requestContext": {
            "authorizer": {
                "jwt": {
                    "claims": {
                        "sub": "user-id"
                    }
                }
            }
        }
    }
    """
    try:
        # Parse request body
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})
        
        # Validate order
        is_valid, error_message = validate_order(body)
        if not is_valid:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': error_message})
            }
        
        # Extract user ID from JWT claims (if authenticated)
        user_id = 'anonymous'
        if 'requestContext' in event:
            authorizer = event['requestContext'].get('authorizer', {})
            if 'jwt' in authorizer:
                user_id = authorizer['jwt'].get('claims', {}).get('sub', 'anonymous')
        
        # Create order message
        order_id = str(uuid.uuid4())
        order_message = {
            'order_id': order_id,
            'user_id': user_id,
            'symbol': body['symbol'].upper(),
            'side': body['side'].lower(),
            'order_type': body['order_type'].lower(),
            'quantity': float(body['quantity']),
            'price': float(body.get('price', 0)) if body['order_type'].lower() == 'limit' else None,
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'pending'
        }
        
        # Send to SQS FIFO queue
        # Use symbol as MessageGroupId to ensure orders for same trading pair are processed in order
        get_sqs_client().send_message(
            QueueUrl=ORDERS_QUEUE_URL,
            MessageBody=json.dumps(order_message),
            MessageGroupId=order_message['symbol']
        )
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'Order submitted successfully',
                'order_id': order_id,
                'order': order_message
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
