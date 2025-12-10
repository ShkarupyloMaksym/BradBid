"""
Matcher Lambda (Krок 7)
Processes orders from SQS orders.fifo queue
Implements order book matching logic using Redis
Saves trades to DynamoDB and sends to trades.fifo
"""
import json
import os
import boto3
import uuid
from datetime import datetime
from decimal import Decimal
import redis

# AWS clients
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')
firehose = boto3.client('firehose')

# Environment variables
REDIS_HOST = os.environ.get('REDIS_HOST')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
DYNAMO_TABLE = os.environ.get('DYNAMO_TABLE')
TRADES_QUEUE_URL = os.environ.get('TRADES_QUEUE_URL')
FIREHOSE_STREAM = os.environ.get('FIREHOSE_STREAM', '')

# Redis connection
redis_client = None


def get_redis_client():
    """Get or create Redis connection."""
    global redis_client
    if redis_client is None:
        redis_client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            decode_responses=True
        )
    return redis_client


def get_order_book_key(symbol: str, side: str) -> str:
    """Generate Redis key for order book."""
    return f"orderbook:{symbol}:{side}"


def add_order_to_book(order: dict) -> None:
    """Add an order to the Redis order book."""
    r = get_redis_client()
    key = get_order_book_key(order['symbol'], order['side'])
    
    # For buy orders, higher price = higher priority (negative score)
    # For sell orders, lower price = higher priority (positive score)
    if order['side'] == 'buy':
        score = -float(order['price']) if order['price'] else float('inf')
    else:
        score = float(order['price']) if order['price'] else 0
    
    # Store order in sorted set with price as score
    r.zadd(key, {json.dumps(order): score})


def get_matching_orders(order: dict) -> list:
    """Get orders that can match with the incoming order."""
    r = get_redis_client()
    
    # For buy orders, look at sell book; for sell orders, look at buy book
    opposite_side = 'sell' if order['side'] == 'buy' else 'buy'
    key = get_order_book_key(order['symbol'], opposite_side)
    
    # Get all orders from the opposite side sorted by price
    orders = r.zrange(key, 0, -1, withscores=True)
    
    matching_orders = []
    for order_json, score in orders:
        book_order = json.loads(order_json)
        
        # Check price match for limit orders
        if order['order_type'] == 'market':
            # Market orders match any price
            matching_orders.append(book_order)
        elif order['order_type'] == 'limit':
            # Limit orders match if price is acceptable
            if order['side'] == 'buy' and float(book_order['price']) <= float(order['price']):
                matching_orders.append(book_order)
            elif order['side'] == 'sell' and float(book_order['price']) >= float(order['price']):
                matching_orders.append(book_order)
    
    return matching_orders


def remove_order_from_book(order: dict) -> None:
    """Remove an order from the Redis order book."""
    r = get_redis_client()
    key = get_order_book_key(order['symbol'], order['side'])
    r.zrem(key, json.dumps(order))


def execute_trade(buy_order: dict, sell_order: dict, quantity: float, price: float) -> dict:
    """Create a trade record."""
    trade = {
        'trade_id': str(uuid.uuid4()),
        'symbol': buy_order['symbol'],
        'buy_order_id': buy_order['order_id'],
        'sell_order_id': sell_order['order_id'],
        'buyer_id': buy_order['user_id'],
        'seller_id': sell_order['user_id'],
        'quantity': quantity,
        'price': price,
        'timestamp': datetime.utcnow().isoformat(),
        'total_value': quantity * price
    }
    return trade


def save_trade_to_dynamodb(trade: dict) -> None:
    """Save trade to DynamoDB."""
    table = dynamodb.Table(DYNAMO_TABLE)
    
    # Convert floats to Decimal for DynamoDB
    item = {
        'TradeId': trade['trade_id'],
        'Symbol': trade['symbol'],
        'BuyOrderId': trade['buy_order_id'],
        'SellOrderId': trade['sell_order_id'],
        'BuyerId': trade['buyer_id'],
        'SellerId': trade['seller_id'],
        'Quantity': Decimal(str(trade['quantity'])),
        'Price': Decimal(str(trade['price'])),
        'TotalValue': Decimal(str(trade['total_value'])),
        'Timestamp': trade['timestamp']
    }
    
    table.put_item(Item=item)


def send_trade_to_queue(trade: dict) -> None:
    """Send trade to SQS trades.fifo queue for broadcasting."""
    sqs.send_message(
        QueueUrl=TRADES_QUEUE_URL,
        MessageBody=json.dumps(trade),
        MessageGroupId=trade['symbol']
    )


def send_trade_to_firehose(trade: dict) -> None:
    """Send trade to Firehose for analytics."""
    if FIREHOSE_STREAM:
        firehose.put_record(
            DeliveryStreamName=FIREHOSE_STREAM,
            Record={'Data': json.dumps(trade) + '\n'}
        )


def process_order(order: dict) -> list:
    """Process an incoming order and attempt to match it."""
    trades = []
    remaining_quantity = float(order['quantity'])
    
    # Get matching orders from the order book
    matching_orders = get_matching_orders(order)
    
    for match_order in matching_orders:
        if remaining_quantity <= 0:
            break
        
        # Determine trade quantity (minimum of both orders)
        match_quantity = float(match_order['quantity'])
        trade_quantity = min(remaining_quantity, match_quantity)
        
        # Determine trade price (maker's price for limit orders)
        trade_price = float(match_order['price']) if match_order.get('price') else float(order.get('price', 0))
        
        # Determine buy and sell orders
        if order['side'] == 'buy':
            buy_order, sell_order = order, match_order
        else:
            buy_order, sell_order = match_order, order
        
        # Execute trade
        trade = execute_trade(buy_order, sell_order, trade_quantity, trade_price)
        trades.append(trade)
        
        # Update remaining quantities
        remaining_quantity -= trade_quantity
        match_order['quantity'] = match_quantity - trade_quantity
        
        # Remove or update the matched order in the book
        remove_order_from_book(match_order)
        if match_order['quantity'] > 0:
            add_order_to_book(match_order)
    
    # If order not fully filled, add remainder to order book (for limit orders)
    if remaining_quantity > 0 and order['order_type'] == 'limit':
        order['quantity'] = remaining_quantity
        order['status'] = 'partial' if trades else 'pending'
        add_order_to_book(order)
    
    return trades


def lambda_handler(event, context):
    """
    Handle incoming orders from SQS orders.fifo queue.
    
    Expected event structure (SQS):
    {
        "Records": [
            {
                "body": "{\"order_id\": \"...\", \"symbol\": \"BTC-USD\", ...}"
            }
        ]
    }
    """
    processed_trades = []
    
    for record in event.get('Records', []):
        try:
            order = json.loads(record['body'])
            print(f"Processing order: {order['order_id']}")
            
            # Process order and get any resulting trades
            trades = process_order(order)
            
            # Save and broadcast trades
            for trade in trades:
                save_trade_to_dynamodb(trade)
                send_trade_to_queue(trade)
                send_trade_to_firehose(trade)
                processed_trades.append(trade)
                print(f"Trade executed: {trade['trade_id']}")
            
        except Exception as e:
            print(f"Error processing order: {str(e)}")
            raise  # Re-raise to trigger SQS retry
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Processed {len(event.get('Records', []))} orders",
            'trades_executed': len(processed_trades)
        })
    }
