import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

# Получаем переменные
TABLE_NAME = os.environ.get('WS_CONNECTIONS_TABLE')
API_ID = os.environ.get('WEBSOCKET_API_ID')
STAGE = os.environ.get('WEBSOCKET_STAGE', 'dev')
REGION = os.environ.get('AWS_REGION', 'eu-west-1')

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    # 1. Формируем URL для отправки (ОЧЕНЬ ВАЖНО)
    # Формат должен быть HTTPS, не WSS
    endpoint_url = f"https://{API_ID}.execute-api.{REGION}.amazonaws.com/{STAGE}"
    logger.info(f"API Gateway Management URL: {endpoint_url}")
    
    # Создаем клиента для отправки сообщений
    apigw_management = boto3.client(
        'apigatewaymanagementapi',
        endpoint_url=endpoint_url,
        region_name=REGION
    )
    
    table = dynamodb.Table(TABLE_NAME)

    # 2. Обрабатываем записи из SQS
    for record in event.get('Records', []):
        try:
            body = record['body']
            logger.info(f"Processing message: {body}")
            
            # Парсим сообщение (это JSON сделки)
            trade_data = json.loads(body)
            
            # Формируем сообщение для клиента
            message_to_send = {
                'type': 'trade',
                'data': trade_data
            }
            message_json = json.dumps(message_to_send).encode('utf-8')
            
            # 3. Получаем всех подключенных клиентов
            # (Для MVP делаем Scan, в проде так не делать)
            scan_resp = table.scan()
            items = scan_resp.get('Items', [])
            logger.info(f"Found {len(items)} connections")
            
            if not items:
                logger.warning("No active connections found.")
                continue

            # 4. Рассылаем
            for item in items:
                connection_id = item['ConnectionId']
                try:
                    apigw_management.post_to_connection(
                        ConnectionId=connection_id,
                        Data=message_json
                    )
                    logger.info(f"Sent to {connection_id}")
                except apigw_management.exceptions.GoneException:
                    logger.warning(f"Connection {connection_id} is gone, deleting.")
                    table.delete_item(Key={'ConnectionId': connection_id})
                except Exception as e:
                    logger.error(f"Failed to send to {connection_id}: {str(e)}")
                    
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            # Не падаем, чтобы обработать остальные записи (если есть)

    return {'statusCode': 200}