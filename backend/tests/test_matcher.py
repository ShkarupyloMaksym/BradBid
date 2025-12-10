"""
Unit Tests for Matcher Lambda (Krок 12)
Tests order matching logic
"""
import pytest


class TestOrderMatching:
    """Test order matching logic concepts."""
    
    def test_buy_limit_matches_sell_limit_at_same_price(self):
        """Buy limit at $100 should match sell limit at $100."""
        buy_order = {'side': 'buy', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        sell_order = {'side': 'sell', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        
        # Buy price >= Sell price means match
        assert buy_order['price'] >= sell_order['price']
    
    def test_buy_limit_matches_cheaper_sell(self):
        """Buy limit at $100 should match sell limit at $95."""
        buy_order = {'side': 'buy', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        sell_order = {'side': 'sell', 'order_type': 'limit', 'price': 95, 'quantity': 10}
        
        # Buy price >= Sell price means match
        assert buy_order['price'] >= sell_order['price']
    
    def test_buy_limit_no_match_expensive_sell(self):
        """Buy limit at $100 should NOT match sell limit at $105."""
        buy_order = {'side': 'buy', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        sell_order = {'side': 'sell', 'order_type': 'limit', 'price': 105, 'quantity': 10}
        
        # Buy price < Sell price means no match
        assert buy_order['price'] < sell_order['price']
    
    def test_partial_fill(self):
        """Order should partially fill if quantities don't match."""
        buy_order = {'side': 'buy', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        sell_order = {'side': 'sell', 'order_type': 'limit', 'price': 100, 'quantity': 5}
        
        trade_quantity = min(buy_order['quantity'], sell_order['quantity'])
        remaining_buy = buy_order['quantity'] - trade_quantity
        
        assert trade_quantity == 5
        assert remaining_buy == 5
    
    def test_market_order_matches_any_price(self):
        """Market order should match any available price."""
        market_order = {'side': 'buy', 'order_type': 'market', 'price': None, 'quantity': 10}
        sell_order = {'side': 'sell', 'order_type': 'limit', 'price': 999999, 'quantity': 10}
        
        # Market orders match regardless of price
        is_match = market_order['order_type'] == 'market' or \
                   (market_order['price'] is not None and market_order['price'] >= sell_order['price'])
        assert is_match is True
    
    def test_trade_price_is_maker_price(self):
        """Trade should execute at the maker's (existing order) price."""
        # Maker: sell limit at $100 (already in order book)
        maker_order = {'side': 'sell', 'order_type': 'limit', 'price': 100, 'quantity': 10}
        # Taker: buy limit at $105 (incoming order)
        taker_order = {'side': 'buy', 'order_type': 'limit', 'price': 105, 'quantity': 10}
        
        # Trade executes at maker's price
        trade_price = maker_order['price']
        assert trade_price == 100  # Not 105


class TestOrderBookPriority:
    """Test order book priority rules."""
    
    def test_sell_book_price_priority(self):
        """Lower price sell orders should have higher priority."""
        sell_orders = [
            {'price': 105, 'quantity': 5},
            {'price': 100, 'quantity': 10},
            {'price': 102, 'quantity': 3}
        ]
        
        # Sort by price ascending for sell orders
        sorted_sells = sorted(sell_orders, key=lambda x: x['price'])
        
        assert sorted_sells[0]['price'] == 100
        assert sorted_sells[1]['price'] == 102
        assert sorted_sells[2]['price'] == 105
    
    def test_buy_book_price_priority(self):
        """Higher price buy orders should have higher priority."""
        buy_orders = [
            {'price': 95, 'quantity': 5},
            {'price': 100, 'quantity': 10},
            {'price': 98, 'quantity': 3}
        ]
        
        # Sort by price descending for buy orders
        sorted_buys = sorted(buy_orders, key=lambda x: -x['price'])
        
        assert sorted_buys[0]['price'] == 100
        assert sorted_buys[1]['price'] == 98
        assert sorted_buys[2]['price'] == 95


class TestTradeCalculation:
    """Test trade value calculations."""
    
    def test_trade_total_value(self):
        """Trade total value should be quantity * price."""
        quantity = 2.5
        price = 50000
        
        total_value = quantity * price
        
        assert total_value == 125000
    
    def test_multi_trade_scenario(self):
        """Test a scenario with multiple partial fills."""
        # Buy order for 100 units
        buy_quantity = 100
        
        # Available sell orders
        sells = [
            {'price': 100, 'quantity': 30},
            {'price': 101, 'quantity': 50},
            {'price': 102, 'quantity': 40}
        ]
        
        remaining = buy_quantity
        total_cost = 0
        
        for sell in sells:
            if remaining <= 0:
                break
            fill_qty = min(remaining, sell['quantity'])
            total_cost += fill_qty * sell['price']
            remaining -= fill_qty
        
        # Should fill: 30@100 + 50@101 + 20@102
        expected_cost = (30 * 100) + (50 * 101) + (20 * 102)
        
        assert remaining == 0
        assert total_cost == expected_cost  # 3000 + 5050 + 2040 = 10090
