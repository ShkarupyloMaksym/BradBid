"""
WebSocket Handler Lambda (Krок 8)
Handles WebSocket connections, disconnections, and subscriptions
Stores connection information in DynamoDB
"""
import json
import os
import boto3
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
CONNECTIONS_TABLE = os.environ.get('CONNECTIONS_TABLE')

# TTL for connections (24 hours)
CONNECTION_TTL_HOURS = 24


def lambda_handler(event, context):
    """
    Handle WebSocket events from API Gateway.
    
    Routes:
    - $connect: New connection established
    - $disconnect: Connection closed
    - subscribe: Client subscribing to symbol updates
    - $default: Handle unknown routes
    """
    route_key = event.get('requestContext', {}).get('routeKey')
    connection_id = event.get('requestContext', {}).get('connectionId')
    
    print(f"Route: {route_key}, ConnectionId: {connection_id}")
    
    if route_key == '$connect':
        return handle_connect(connection_id)
    elif route_key == '$disconnect':
        return handle_disconnect(connection_id)
    elif route_key == 'subscribe':
        return handle_subscribe(connection_id, event)
    else:
        return handle_default(connection_id, event)


def handle_connect(connection_id: str) -> dict:
    """Handle new WebSocket connection."""
    table = dynamodb.Table(CONNECTIONS_TABLE)
    
    # Calculate TTL (24 hours from now)
    ttl = int((datetime.utcnow() + timedelta(hours=CONNECTION_TTL_HOURS)).timestamp())
    
    table.put_item(
        Item={
            'ConnectionId': connection_id,
            'ConnectedAt': datetime.utcnow().isoformat(),
            'Subscriptions': [],  # Will hold list of symbols
            'TTL': ttl
        }
    )
    
    print(f"Connection established: {connection_id}")
    return {'statusCode': 200, 'body': 'Connected'}


def handle_disconnect(connection_id: str) -> dict:
    """Handle WebSocket disconnection."""
    table = dynamodb.Table(CONNECTIONS_TABLE)
    
    try:
        table.delete_item(Key={'ConnectionId': connection_id})
        print(f"Connection removed: {connection_id}")
    except Exception as e:
        print(f"Error removing connection: {str(e)}")
    
    return {'statusCode': 200, 'body': 'Disconnected'}


def handle_subscribe(connection_id: str, event: dict) -> dict:
    """
    Handle subscription request.
    
    Expected message format:
    {
        "action": "subscribe",
        "symbols": ["BTC-USD", "ETH-USD"]
    }
    """
    table = dynamodb.Table(CONNECTIONS_TABLE)
    
    try:
        body = json.loads(event.get('body', '{}'))
        symbols = body.get('symbols', [])
        
        if not symbols:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No symbols provided'})
            }
        
        # Normalize symbols to uppercase
        symbols = [s.upper() for s in symbols]
        
        # Update subscription list
        table.update_item(
            Key={'ConnectionId': connection_id},
            UpdateExpression='SET Subscriptions = :symbols',
            ExpressionAttributeValues={':symbols': symbols}
        )
        
        print(f"Connection {connection_id} subscribed to: {symbols}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Subscribed successfully',
                'symbols': symbols
            })
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON'})
        }
    except Exception as e:
        print(f"Error handling subscription: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }


def handle_default(connection_id: str, event: dict) -> dict:
    """Handle unknown routes with a helpful message."""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Unknown action. Supported actions: subscribe',
            'example': {
                'action': 'subscribe',
                'symbols': ['BTC-USD', 'ETH-USD']
            }
        })
    }
