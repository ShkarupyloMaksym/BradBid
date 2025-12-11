"""
Trade Broadcaster Lambda (Krок 8)
Listens to trades.fifo queue and broadcasts trade updates to WebSocket clients
Uses API Gateway Management API to send messages to connected clients
"""
import json
import os
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb')
CONNECTIONS_TABLE = os.environ.get('CONNECTIONS_TABLE')
WEBSOCKET_API_ENDPOINT = os.environ.get('WEBSOCKET_API_ENDPOINT')


def get_subscribed_connections(symbol: str) -> list:
    """Get all connections subscribed to a specific symbol."""
    table = dynamodb.Table(CONNECTIONS_TABLE)
    
    # Scan for connections that have the symbol in their subscriptions
    # Note: For production, consider using a GSI for better performance
    response = table.scan(
        FilterExpression=Attr('Subscriptions').contains(symbol)
    )
    
    return response.get('Items', [])


def send_message_to_connection(api_client, connection_id: str, message: dict) -> bool:
    """Send a message to a specific WebSocket connection."""
    try:
        api_client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message).encode('utf-8')
        )
        return True
    except api_client.exceptions.GoneException:
        # Connection no longer exists, clean up
        print(f"Connection {connection_id} is gone, removing from table")
        table = dynamodb.Table(CONNECTIONS_TABLE)
        table.delete_item(Key={'ConnectionId': connection_id})
        return False
    except Exception as e:
        print(f"Error sending to {connection_id}: {str(e)}")
        return False


def broadcast_trade(trade: dict) -> dict:
    """Broadcast a trade to all subscribed WebSocket connections."""
    symbol = trade.get('symbol')
    if not symbol:
        return {'sent': 0, 'failed': 0}
    
    # Get all connections subscribed to this symbol
    connections = get_subscribed_connections(symbol)
    
    if not connections:
        print(f"No connections subscribed to {symbol}")
        return {'sent': 0, 'failed': 0}
    
    # Create API Gateway Management API client
    api_client = boto3.client(
        'apigatewaymanagementapi',
        endpoint_url=WEBSOCKET_API_ENDPOINT
    )
    
    # Prepare the message
    message = {
        'type': 'trade',
        'data': {
            'trade_id': trade['trade_id'],
            'symbol': trade['symbol'],
            'price': trade['price'],
            'quantity': trade['quantity'],
            'total_value': trade['total_value'],
            'timestamp': trade['timestamp']
        }
    }
    
    sent_count = 0
    failed_count = 0
    
    for connection in connections:
        connection_id = connection['ConnectionId']
        if send_message_to_connection(api_client, connection_id, message):
            sent_count += 1
        else:
            failed_count += 1
    
    return {'sent': sent_count, 'failed': failed_count}


def lambda_handler(event, context):
    """
    Handle incoming trades from SQS trades.fifo queue and broadcast to WebSocket clients.
    
    Expected event structure (SQS):
    {
        "Records": [
            {
                "body": "{\"trade_id\": \"...\", \"symbol\": \"BTC-USD\", ...}"
            }
        ]
    }
    """
    total_sent = 0
    total_failed = 0
    
    for record in event.get('Records', []):
        try:
            trade = json.loads(record['body'])
            print(f"Broadcasting trade: {trade.get('trade_id')}")
            
            result = broadcast_trade(trade)
            total_sent += result['sent']
            total_failed += result['failed']
            
            print(f"Trade {trade.get('trade_id')}: sent to {result['sent']} clients, {result['failed']} failed")
            
        except json.JSONDecodeError:
            print(f"Invalid JSON in record: {record.get('body')}")
        except Exception as e:
            print(f"Error broadcasting trade: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Broadcast {len(event.get('Records', []))} trades",
            'total_sent': total_sent,
            'total_failed': total_failed
        })
    }
