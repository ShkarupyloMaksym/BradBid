"""
Ingest Lambda Function
Validates incoming orders and publishes them to Kinesis Data Stream
"""
import json
import os
import uuid
import time
from typing import Dict, Any
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch boto3 for X-Ray tracing
patch_all()

# Initialize AWS clients
kinesis_client = boto3.client('kinesis')
dynamodb_client = boto3.client('dynamodb')

# Environment variables
KINESIS_STREAM = os.environ.get('KINESIS_ORDERS_STREAM')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_ORDERS_TABLE', '')


def validate_order(order: Dict[str, Any]) -> tuple[bool, str]:
    """
    Validate order structure and values
    
    Expected format:
    {
        "orderId": "string",
        "symbol": "string",
        "side": "BUY" | "SELL",
        "quantity": number,
        "price": number,
        "timestamp": number (optional)
    }
    """
    required_fields = ['orderId', 'symbol', 'side', 'quantity', 'price']
    
    # Check required fields
    for field in required_fields:
        if field not in order:
            return False, f"Missing required field: {field}"
    
    # Validate side
    if order['side'] not in ['BUY', 'SELL']:
        return False, "side must be 'BUY' or 'SELL'"
    
    # Validate quantity and price are positive numbers
    try:
        quantity = float(order['quantity'])
        price = float(order['price'])
        
        if quantity <= 0:
            return False, "quantity must be positive"
        if price <= 0:
            return False, "price must be positive"
    except (ValueError, TypeError):
        return False, "quantity and price must be numeric"
    
    # Validate symbol is non-empty string
    if not isinstance(order['symbol'], str) or len(order['symbol'].strip()) == 0:
        return False, "symbol must be a non-empty string"
    
    return True, "OK"


@xray_recorder.capture('ingest_order')
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for order ingestion
    
    API Gateway event format expected
    """
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        # Validate order
        is_valid, error_message = validate_order(body)
        if not is_valid:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Validation failed',
                    'message': error_message
                })
            }
        
        # Add timestamp if not present
        if 'timestamp' not in body:
            body['timestamp'] = int(time.time() * 1000)  # milliseconds
        
        # Generate order ID if not present
        if 'orderId' not in body or not body['orderId']:
            body['orderId'] = str(uuid.uuid4())
        
        # Put record to Kinesis
        partition_key = f"{body['symbol']}-{body['side']}"
        
        response = kinesis_client.put_record(
            StreamName=KINESIS_STREAM,
            Data=json.dumps(body),
            PartitionKey=partition_key
        )
        
        # Optionally write to DynamoDB for audit trail
        if DYNAMODB_TABLE:
            try:
                dynamodb_client.put_item(
                    TableName=DYNAMODB_TABLE,
                    Item={
                        'OrderId': {'S': body['orderId']},
                        'Symbol': {'S': body['symbol']},
                        'Side': {'S': body['side']},
                        'Quantity': {'N': str(body['quantity'])},
                        'Price': {'N': str(body['price'])},
                        'Timestamp': {'N': str(body['timestamp'])},
                        'Status': {'S': 'PENDING'},
                        'KinesisSequenceNumber': {'S': response['SequenceNumber']}
                    }
                )
            except Exception as db_error:
                # Log error but don't fail the request
                print(f"Failed to write to DynamoDB: {str(db_error)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Order accepted',
                'orderId': body['orderId'],
                'sequenceNumber': response['SequenceNumber']
            })
        }
    
    except json.JSONDecodeError as e:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON',
                'message': str(e)
            })
        }
    
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to process order'
            })
        }

