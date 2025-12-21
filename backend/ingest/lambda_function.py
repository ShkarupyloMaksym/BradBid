import json
import boto3
import os
import logging
import uuid
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize SQS client
sqs = boto3.client('sqs')

# Environment variables
QUEUE_URL = os.environ.get('QUEUE_URL')

# Жесткие CORS заголовки для всех ответов
CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Allow-Methods': 'OPTIONS,POST'
}

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Ingest Lambda function - receives order requests from API Gateway
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # 1. ВАЖНО: Обработка OPTIONS запроса (Preflight)
        # Браузер спрашивает: "Можно ли мне слать POST?" - Мы отвечаем: "Да!"
        # Проверяем оба варианта (для REST API и HTTP API)
        http_method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method')
        
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': ''
            }

        # 2. Parse request body
        body = parse_request_body(event)
        if not body:
            return error_response(400, "Invalid request body")
        
        # 3. Validate order data
        validation_error = validate_order(body)
        if validation_error:
            return error_response(400, validation_error)
        
        # 4. Determine User ID (Cognito OR Body)
        user_id = extract_user_id(event)
        # Если авторизации нет (тест), берем из формы
        if user_id == 'anonymous' and 'user_id' in body:
            user_id = body['user_id']

        # 5. Generate IDs
        order_id = generate_order_id()
        
        # 6. Prepare order message
        order_data = {
            'orderId': order_id,
            'pair': body['pair'],
            'side': body.get('side', 'BUY'),
            'price': float(body['price']),
            'amount': float(body['amount']),
            'timestamp': datetime.utcnow().isoformat(),
            'userId': user_id
        }
        
        # 7. Send to SQS FIFO queue
        response = send_to_queue(order_data)
        
        logger.info(f"Order sent to queue: {order_data['orderId']}")
        
        return success_response(200, {
            'orderId': order_data['orderId'],
            'status': 'queued',
            'messageId': response.get('MessageId', '')
        })
        
    except Exception as e:
        logger.error(f"Error processing order: {str(e)}", exc_info=True)
        # Даже при ошибке возвращаем CORS заголовки!
        return error_response(500, f"Internal server error: {str(e)}")


def parse_request_body(event: Dict[str, Any]) -> Dict[str, Any]:
    try:
        if 'body' not in event:
            return {}
        
        body = event['body']
        if not body:
            return {}
            
        if isinstance(body, str):
            return json.loads(body)
        return body
    except Exception as e:
        logger.error(f"JSON decode error: {str(e)}")
        return None


def validate_order(order: Dict[str, Any]) -> str:
    required_fields = ['price', 'amount', 'pair']
    for field in required_fields:
        if field not in order:
            return f"Missing required field: {field}"
    
    try:
        if float(order['price']) <= 0:
            return "Price must be greater than 0"
    except (ValueError, TypeError):
        return "Invalid price format"
    
    try:
        if float(order['amount']) <= 0:
            return "Amount must be greater than 0"
    except (ValueError, TypeError):
        return "Invalid amount format"
    
    return None


def send_to_queue(order_data: Dict[str, Any]) -> Dict[str, Any]:
    if not QUEUE_URL:
        raise ValueError("QUEUE_URL environment variable not set")
    
    return sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(order_data),
        MessageGroupId=order_data['pair'],
        MessageDeduplicationId=order_data['orderId']
    )


def generate_order_id() -> str:
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    unique_id = str(uuid.uuid4())[:8]
    return f"ORD-{timestamp}-{unique_id}"


def extract_user_id(event: Dict[str, Any]) -> str:
    try:
        claims = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {})
        user_id = claims.get('sub') or claims.get('username')
        return user_id if user_id else 'anonymous'
    except:
        return 'anonymous'


def success_response(status_code: int, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        'statusCode': status_code,
        'headers': CORS_HEADERS,
        'body': json.dumps(data)
    }


def error_response(status_code: int, message: str) -> Dict[str, Any]:
    return {
        'statusCode': status_code,
        'headers': CORS_HEADERS,
        'body': json.dumps({'error': message})
    }