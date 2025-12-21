import json
import boto3
import os
import logging
from datetime import datetime, timedelta

# Настройка логирования
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Инициализация DynamoDB
dynamodb = boto3.resource('dynamodb')
WS_CONNECTIONS_TABLE = os.environ.get('WS_CONNECTIONS_TABLE')

def lambda_handler(event, context):
    try:
        # Получаем данные события
        route_key = event.get('requestContext', {}).get('routeKey')
        connection_id = event.get('requestContext', {}).get('connectionId')
        
        print(f"WebSocket Event: Route={route_key}, ConnectionId={connection_id}")
        
        # Если таблица не задана (локальный тест), просто логируем
        if not WS_CONNECTIONS_TABLE:
            print("ERROR: WS_CONNECTIONS_TABLE is not set")
            return {'statusCode': 500, 'body': 'Configuration error'}

        table = dynamodb.Table(WS_CONNECTIONS_TABLE)
        
        # Маршрутизация
        if route_key == '$connect':
            return handle_connect(table, connection_id)
        elif route_key == '$disconnect':
            return handle_disconnect(table, connection_id)
        elif route_key == '$default':
            return {'statusCode': 200, 'body': 'Message received'}
        else:
            return {'statusCode': 400, 'body': 'Unknown route'}
            
    except Exception as e:
        print(f"CRITICAL ERROR: {str(e)}")
        return {'statusCode': 500, 'body': 'Internal server error'}

def handle_connect(table, connection_id):
    try:
        # TTL = 24 часа
        ttl = int((datetime.utcnow() + timedelta(hours=24)).timestamp())
        
        print(f"Saving connection {connection_id} to table {table.name}")
        
        table.put_item(
            Item={
                'ConnectionId': connection_id,
                'ConnectedAt': datetime.utcnow().isoformat(),
                'TTL': ttl
            }
        )
        print("Successfully saved connection")
        return {'statusCode': 200, 'body': 'Connected'}
    except Exception as e:
        print(f"Error saving connection: {str(e)}")
        return {'statusCode': 500, 'body': 'Failed to connect'}

def handle_disconnect(table, connection_id):
    try:
        print(f"Removing connection {connection_id}")
        table.delete_item(Key={'ConnectionId': connection_id})
        print("Successfully removed connection")
        return {'statusCode': 200, 'body': 'Disconnected'}
    except Exception as e:
        print(f"Error removing connection: {str(e)}")
        return {'statusCode': 200, 'body': 'Disconnected'} # Все равно возвращаем 200, чтобы не держать сокет