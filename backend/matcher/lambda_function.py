import json
import boto3
import redis
import os
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional, Tuple
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

# Environment variables
REDIS_HOST = os.environ.get('REDIS_HOST')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
TRADES_TABLE_NAME = os.environ.get('TRADES_TABLE_NAME')
TRADES_QUEUE_URL = os.environ.get('TRADES_QUEUE_URL')

# Initialize Redis client (lazy connection)
redis_client = None


def get_redis_client():
    """Get or create Redis client."""
    global redis_client
    if redis_client is None:
        redis_client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5
        )
    return redis_client


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Matcher Lambda function - processes orders from SQS queue,
    matches buy/sell orders, and executes trades.
    
    Args:
        event: SQS event containing order messages
        context: Lambda context
        
    Returns:
        Response with batch item failures (for partial batch failure)
    """
    batch_item_failures = []
    
    try:
        logger.info(f"Processing {len(event['Records'])} order(s)")
        
        # Connect to Redis
        r = get_redis_client()
        r.ping()  # Test connection
        logger.info("Connected to Redis")
        
        # Initialize DynamoDB table
        trades_table = dynamodb.Table(TRADES_TABLE_NAME)
        
        # Process each order in the batch
        for record in event['Records']:
            try:
                # Parse order from SQS message
                order = json.loads(record['body'])
                logger.info(f"Processing order: {order['orderId']}")
                
                # Process the order and attempt matching
                process_order(r, trades_table, order)
                
            except Exception as e:
                logger.error(f"Error processing order {record.get('messageId')}: {str(e)}", exc_info=True)
                # Add to batch item failures for SQS retry
                batch_item_failures.append({
                    'itemIdentifier': record['messageId']
                })
        
        # Return batch item failures for partial batch failure handling
        return {
            'batchItemFailures': batch_item_failures
        }
        
    except Exception as e:
        logger.error(f"Critical error in matcher: {str(e)}", exc_info=True)
        # If Redis connection fails, fail entire batch
        raise


def process_order(r: redis.Redis, trades_table: Any, order: Dict[str, Any]) -> None:
    """
    Process incoming order: attempt to match with existing orders
    or add to order book.
    
    Args:
        r: Redis client
        trades_table: DynamoDB trades table
        order: Order data
    """
    pair = order['pair']
    side = order['side'].upper()
    price = float(order['price'])
    amount = float(order['amount'])
    order_id = order['orderId']
    
    logger.info(f"Order: {side} {amount} {pair} @ {price}")
    
    # Try to match the order
    matched = False
    
    if side == 'BUY':
        # For BUY order, look for SELL orders with price <= buy price
        matched = match_buy_order(r, trades_table, order, pair, price, amount)
    else:  # SELL
        # For SELL order, look for BUY orders with price >= sell price
        matched = match_sell_order(r, trades_table, order, pair, price, amount)
    
    if not matched:
        # No match found, add order to order book
        add_to_order_book(r, order)
        logger.info(f"Order {order_id} added to order book (no match)")


def match_buy_order(r: redis.Redis, trades_table: Any, buy_order: Dict[str, Any], 
                    pair: str, buy_price: float, buy_amount: float) -> bool:
    """
    Match a BUY order against SELL orders in the order book.
    
    Returns:
        True if matched, False otherwise
    """
    # Get best SELL orders (lowest price first)
    sell_orders_key = f"orderbook:{pair}:SELL"
    
    # Get SELL orders with price <= buy_price using ZRANGEBYSCORE
    # Score in Redis sorted set represents the price
    sell_orders = r.zrangebyscore(sell_orders_key, 0, buy_price, withscores=True)
    
    if not sell_orders:
        return False
    
    # Process the best (lowest priced) sell order
    sell_order_data, sell_price = sell_orders[0]
    sell_order = json.loads(sell_order_data)
    sell_amount = float(sell_order['amount'])
    
    logger.info(f"Match found: BUY @ {buy_price} with SELL @ {sell_price}")
    
    # Execute trade at the sell price (maker price)
    trade_amount = min(buy_amount, sell_amount)
    trade_price = sell_price  # Trade executes at maker (sell) price
    
    execute_trade(r, trades_table, buy_order, sell_order, pair, trade_price, trade_amount)
    
    # Update or remove sell order from order book
    remaining_sell_amount = sell_amount - trade_amount
    if remaining_sell_amount > 0:
        # Update sell order with remaining amount
        sell_order['amount'] = remaining_sell_amount
        r.zadd(sell_orders_key, {json.dumps(sell_order): sell_price})
    else:
        # Remove completely filled sell order
        r.zrem(sell_orders_key, sell_order_data)
    
    # If buy order is partially filled, add remainder to order book
    remaining_buy_amount = buy_amount - trade_amount
    if remaining_buy_amount > 0:
        buy_order['amount'] = remaining_buy_amount
        add_to_order_book(r, buy_order)
    
    return True


def match_sell_order(r: redis.Redis, trades_table: Any, sell_order: Dict[str, Any],
                     pair: str, sell_price: float, sell_amount: float) -> bool:
    """
    Match a SELL order against BUY orders in the order book.
    
    Returns:
        True if matched, False otherwise
    """
    # Get best BUY orders (highest price first)
    buy_orders_key = f"orderbook:{pair}:BUY"
    
    # Get BUY orders with price >= sell_price using ZREVRANGEBYSCORE
    # (reverse to get highest prices first)
    buy_orders = r.zrevrangebyscore(buy_orders_key, '+inf', sell_price, withscores=True)
    
    if not buy_orders:
        return False
    
    # Process the best (highest priced) buy order
    buy_order_data, buy_price = buy_orders[0]
    buy_order = json.loads(buy_order_data)
    buy_amount = float(buy_order['amount'])
    
    logger.info(f"Match found: SELL @ {sell_price} with BUY @ {buy_price}")
    
    # Execute trade at the buy price (maker price)
    trade_amount = min(sell_amount, buy_amount)
    trade_price = buy_price  # Trade executes at maker (buy) price
    
    execute_trade(r, trades_table, buy_order, sell_order, pair, trade_price, trade_amount)
    
    # Update or remove buy order from order book
    remaining_buy_amount = buy_amount - trade_amount
    if remaining_buy_amount > 0:
        # Update buy order with remaining amount
        buy_order['amount'] = remaining_buy_amount
        r.zadd(buy_orders_key, {json.dumps(buy_order): buy_price})
    else:
        # Remove completely filled buy order
        r.zrem(buy_orders_key, buy_order_data)
    
    # If sell order is partially filled, add remainder to order book
    remaining_sell_amount = sell_amount - trade_amount
    if remaining_sell_amount > 0:
        sell_order['amount'] = remaining_sell_amount
        add_to_order_book(r, sell_order)
    
    return True


def execute_trade(r: redis.Redis, trades_table: Any, buy_order: Dict[str, Any],
                 sell_order: Dict[str, Any], pair: str, price: float, amount: float) -> None:
    """
    Execute a trade: save to DynamoDB and send to trades queue.
    
    Args:
        r: Redis client
        trades_table: DynamoDB trades table
        buy_order: Buy order data
        sell_order: Sell order data
        pair: Trading pair
        price: Trade execution price
        amount: Trade amount
    """
    import uuid
    
    # Generate trade ID
    trade_id = f"TRD-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{str(uuid.uuid4())[:8]}"
    timestamp = datetime.utcnow().isoformat()
    
    trade_data = {
        'tradeId': trade_id,
        'pair': pair,
        'price': str(price),  # Store as string to preserve precision
        'amount': str(amount),
        'buyOrderId': buy_order['orderId'],
        'sellOrderId': sell_order['orderId'],
        'buyUserId': buy_order.get('userId', 'unknown'),
        'sellUserId': sell_order.get('userId', 'unknown'),
        'timestamp': timestamp
    }
    
    logger.info(f"Executing trade: {trade_id} - {amount} {pair} @ {price}")
    
    # Save trade to DynamoDB
    save_trade_to_dynamodb(trades_table, trade_data)
    
    # Send trade event to SQS trades.fifo queue
    send_trade_event(trade_data)
    
    # Update last trade price in Redis for quote streaming
    r.set(f"lastprice:{pair}", price)


def add_to_order_book(r: redis.Redis, order: Dict[str, Any]) -> None:
    """
    Add order to Redis order book using sorted sets.
    
    Args:
        r: Redis client
        order: Order data
    """
    pair = order['pair']
    side = order['side'].upper()
    price = float(order['price'])
    
    # Key format: orderbook:{pair}:{side}
    key = f"orderbook:{pair}:{side}"
    
    # Store order as JSON string, use price as score for sorting
    order_data = json.dumps(order)
    r.zadd(key, {order_data: price})
    
    logger.info(f"Added {side} order to order book: {pair} @ {price}")


def save_trade_to_dynamodb(trades_table: Any, trade_data: Dict[str, Any]) -> None:
    """Save trade to DynamoDB Trades table."""
    try:
        # Convert float values to Decimal for DynamoDB
        item = {
            'TradeId': trade_data['tradeId'],
            'Pair': trade_data['pair'],
            'Price': Decimal(trade_data['price']),
            'Amount': Decimal(trade_data['amount']),
            'BuyOrderId': trade_data['buyOrderId'],
            'SellOrderId': trade_data['sellOrderId'],
            'BuyUserId': trade_data['buyUserId'],
            'SellUserId': trade_data['sellUserId'],
            'Timestamp': trade_data['timestamp']
        }
        
        trades_table.put_item(Item=item)
        logger.info(f"Trade saved to DynamoDB: {trade_data['tradeId']}")
        
    except Exception as e:
        logger.error(f"Error saving trade to DynamoDB: {str(e)}", exc_info=True)
        raise


def send_trade_event(trade_data: Dict[str, Any]) -> None:
    """Send trade event to SQS trades.fifo queue."""
    try:
        if not TRADES_QUEUE_URL:
            raise ValueError("TRADES_QUEUE_URL environment variable not set")
        
        # Use trading pair as MessageGroupId for FIFO ordering
        message_group_id = trade_data['pair']
        
        response = sqs.send_message(
            QueueUrl=TRADES_QUEUE_URL,
            MessageBody=json.dumps(trade_data),
            MessageGroupId=message_group_id
        )
        
        logger.info(f"Trade event sent to queue: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Error sending trade event to SQS: {str(e)}", exc_info=True)
        raise

# fix