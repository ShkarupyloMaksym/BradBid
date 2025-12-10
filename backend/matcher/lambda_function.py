"""
Matcher Lambda Function
Processes orders from Kinesis, maintains order book in Redis, and matches trades
"""
import json
import os
import uuid
import time
from typing import Dict, Any, List, Optional
import boto3
import redis
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch boto3 for X-Ray tracing
patch_all()

# Initialize AWS clients
kinesis_client = boto3.client('kinesis')
dynamodb_client = boto3.client('dynamodb')
secrets_client = boto3.client('secretsmanager')

# Environment variables
REDIS_SECRET_ARN = os.environ.get('REDIS_SECRET_ARN')
REDIS_ENDPOINT = os.environ.get('REDIS_ENDPOINT')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TRADES_TABLE')
KINESIS_TRADES_STREAM = os.environ.get('KINESIS_TRADES_STREAM')

# Redis connection (lazy initialization)
redis_client: Optional[redis.Redis] = None


def get_redis_client() -> redis.Redis:
    """Get or create Redis client with authentication"""
    global redis_client
    
    if redis_client is not None:
        return redis_client
    
    # Get auth token from Secrets Manager
    try:
        secret_response = secrets_client.get_secret_value(SecretId=REDIS_SECRET_ARN)
        secret_data = json.loads(secret_response['SecretString'])
        auth_token = secret_data.get('auth_token', '')
    except Exception as e:
        print(f"Failed to get Redis auth token: {str(e)}")
        auth_token = None
    
    # Connect to Redis
    redis_client = redis.Redis(
        host=REDIS_ENDPOINT,
        port=REDIS_PORT,
        password=auth_token if auth_token else None,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5
    )
    
    # Test connection
    try:
        redis_client.ping()
    except Exception as e:
        print(f"Failed to connect to Redis: {str(e)}")
        raise
    
    return redis_client


def get_order_book_key(symbol: str, side: str) -> str:
    """Get Redis key for order book"""
    return f"orderbook:{symbol}:{side}"


def add_order_to_book(redis_client: redis.Redis, order: Dict[str, Any]) -> None:
    """
    Add order to order book in Redis
    Uses sorted set for price-time priority matching
    """
    symbol = order['symbol']
    side = order['side']
    price = float(order['price'])
    order_id = order['orderId']
    quantity = float(order['quantity'])
    timestamp = order.get('timestamp', int(time.time() * 1000))
    
    # Redis key for this side of the order book
    key = get_order_book_key(symbol, side)
    
    # Use sorted set: score = price (for BUY: negative for descending, for SELL: positive for ascending)
    # For price-time priority: score = price * 1e10 + timestamp
    # This ensures orders are sorted by price first, then by time
    
    if side == 'BUY':
        # Higher prices first (negative for descending order)
        score = -price * 1e10 + timestamp
    else:  # SELL
        # Lower prices first (positive for ascending order)
        score = price * 1e10 + timestamp
    
    # Store order data as hash
    order_data = {
        'orderId': order_id,
        'symbol': symbol,
        'side': side,
        'price': str(price),
        'quantity': str(quantity),
        'timestamp': str(timestamp)
    }
    
    # Add to sorted set (score for ordering)
    redis_client.zadd(key, {order_id: score})
    
    # Store order details in hash
    redis_client.hset(f"order:{order_id}", mapping=order_data)
    
    # Set expiration (24 hours)
    redis_client.expire(f"order:{order_id}", 86400)


def get_best_order(redis_client: redis.Redis, symbol: str, side: str) -> Optional[Dict[str, Any]]:
    """
    Get the best order from the order book
    For BUY: highest price (first in sorted set)
    For SELL: lowest price (first in sorted set)
    """
    key = get_order_book_key(symbol, side)
    
    # Get first order (best price)
    order_ids = redis_client.zrange(key, 0, 0)
    
    if not order_ids:
        return None
    
    order_id = order_ids[0]
    
    # Get order details
    order_data = redis_client.hgetall(f"order:{order_id}")
    
    if not order_data:
        # Clean up orphaned entry
        redis_client.zrem(key, order_id)
        return None
    
    return order_data


def remove_order_from_book(redis_client: redis.Redis, order_id: str, symbol: str, side: str) -> None:
    """Remove order from order book"""
    key = get_order_book_key(symbol, side)
    redis_client.zrem(key, order_id)
    redis_client.delete(f"order:{order_id}")


def update_order_quantity(redis_client: redis.Redis, order_id: str, remaining_quantity: float) -> None:
    """Update remaining quantity for an order"""
    redis_client.hset(f"order:{order_id}", 'quantity', str(remaining_quantity))


def match_orders(redis_client: redis.Redis, new_order: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Match a new order against the order book
    Returns list of trades executed
    """
    trades = []
    symbol = new_order['symbol']
    side = new_order['side']
    opposite_side = 'SELL' if side == 'BUY' else 'BUY'
    
    remaining_quantity = float(new_order['quantity'])
    new_order_price = float(new_order['price'])
    
    # Check for idempotency - use order ID as key
    idempotency_key = f"processed:{new_order['orderId']}"
    if redis_client.exists(idempotency_key):
        print(f"Order {new_order['orderId']} already processed (idempotency check)")
        return trades
    
    # Mark as processed (expire after 1 hour)
    redis_client.setex(idempotency_key, 3600, "1")
    
    # Try to match while there's remaining quantity
    while remaining_quantity > 0:
        # Get best matching order from opposite side
        best_order = get_best_order(redis_client, symbol, opposite_side)
        
        if not best_order:
            # No more matches, add remaining to order book
            if remaining_quantity > 0:
                new_order['quantity'] = remaining_quantity
                add_order_to_book(redis_client, new_order)
            break
        
        best_price = float(best_order['price'])
        best_quantity = float(best_order['quantity'])
        best_order_id = best_order['orderId']
        
        # Check if prices match
        if side == 'BUY' and new_order_price < best_price:
            # Buy order price too low
            break
        if side == 'SELL' and new_order_price > best_price:
            # Sell order price too high
            break
        
        # Match at the best order's price (price-time priority)
        trade_price = best_price
        trade_quantity = min(remaining_quantity, best_quantity)
        
        # Create trade
        trade = {
            'tradeId': str(uuid.uuid4()),
            'symbol': symbol,
            'buyOrderId': new_order['orderId'] if side == 'BUY' else best_order_id,
            'sellOrderId': new_order['orderId'] if side == 'SELL' else best_order_id,
            'price': trade_price,
            'quantity': trade_quantity,
            'timestamp': int(time.time() * 1000)
        }
        trades.append(trade)
        
        # Update quantities
        remaining_quantity -= trade_quantity
        best_quantity -= trade_quantity
        
        if best_quantity <= 0:
            # Best order fully filled, remove it
            remove_order_from_book(redis_client, best_order_id, symbol, opposite_side)
        else:
            # Update best order quantity
            update_order_quantity(redis_client, best_order_id, best_quantity)
    
    return trades


@xray_recorder.capture('process_order')
def process_order(redis_client: redis.Redis, order: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Process a single order and return trades"""
    try:
        trades = match_orders(redis_client, order)
        return trades
    except Exception as e:
        print(f"Error processing order {order.get('orderId')}: {str(e)}")
        raise


@xray_recorder.capture('save_trade')
def save_trade_to_dynamodb(trade: Dict[str, Any]) -> None:
    """Save trade to DynamoDB"""
    try:
        dynamodb_client.put_item(
            TableName=DYNAMODB_TABLE,
            Item={
                'TradeId': {'S': trade['tradeId']},
                'Symbol': {'S': trade['symbol']},
                'BuyOrderId': {'S': trade['buyOrderId']},
                'SellOrderId': {'S': trade['sellOrderId']},
                'Price': {'N': str(trade['price'])},
                'Quantity': {'N': str(trade['quantity'])},
                'Timestamp': {'N': str(trade['timestamp'])}
            }
        )
    except Exception as e:
        print(f"Failed to save trade to DynamoDB: {str(e)}")
        raise


@xray_recorder.capture('publish_trade')
def publish_trade_to_kinesis(trade: Dict[str, Any]) -> None:
    """Publish trade event to Kinesis"""
    try:
        partition_key = f"{trade['symbol']}-{trade['tradeId']}"
        kinesis_client.put_record(
            StreamName=KINESIS_TRADES_STREAM,
            Data=json.dumps(trade),
            PartitionKey=partition_key
        )
    except Exception as e:
        print(f"Failed to publish trade to Kinesis: {str(e)}")
        raise


@xray_recorder.capture('matcher_handler')
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for order matching
    Triggered by Kinesis event source mapping
    """
    try:
        # Get Redis client
        redis_client = get_redis_client()
        
        # Process Kinesis records
        batch_item_failures = []
        all_trades = []
        
        for record in event.get('Records', []):
            try:
                # Parse Kinesis record
                kinesis_data = record.get('kinesis', {})
                order_data = json.loads(kinesis_data.get('data', '{}'))
                sequence_number = kinesis_data.get('sequenceNumber')
                
                # Process order and get trades
                trades = process_order(redis_client, order_data)
                
                # Process each trade
                for trade in trades:
                    # Save to DynamoDB
                    save_trade_to_dynamodb(trade)
                    
                    # Publish to Kinesis
                    publish_trade_to_kinesis(trade)
                    
                    all_trades.append(trade)
                
            except Exception as e:
                print(f"Error processing record: {str(e)}")
                # Report batch item failure for partial batch failure handling
                batch_item_failures.append({
                    'itemIdentifier': record.get('kinesis', {}).get('sequenceNumber', '')
                })
        
        # Return batch item failures if any
        if batch_item_failures:
            return {
                'batchItemFailures': batch_item_failures
            }
        
        return {
            'statusCode': 200,
            'tradesProcessed': len(all_trades)
        }
    
    except Exception as e:
        print(f"Fatal error in matcher: {str(e)}")
        # Re-raise to trigger retry
        raise

