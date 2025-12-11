"""
Unit Tests for Ingest Lambda (Krок 12)
Tests order validation without AWS dependencies
"""
import json
import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'ingest'))

from lambda_function import validate_order


class TestOrderValidation:
    """Test order validation logic."""
    
    def test_valid_limit_buy_order(self):
        """Test a valid limit buy order passes validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 1.5,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is True
        assert error == ""
    
    def test_valid_limit_sell_order(self):
        """Test a valid limit sell order passes validation."""
        order = {
            'symbol': 'ETH-USD',
            'side': 'sell',
            'order_type': 'limit',
            'quantity': 10,
            'price': 3000
        }
        is_valid, error = validate_order(order)
        assert is_valid is True
        assert error == ""
    
    def test_valid_market_order(self):
        """Test a valid market order (no price required)."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'market',
            'quantity': 0.5
        }
        is_valid, error = validate_order(order)
        assert is_valid is True
        assert error == ""
    
    def test_missing_symbol(self):
        """Test that missing symbol fails validation."""
        order = {
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'symbol' in error.lower()
    
    def test_missing_side(self):
        """Test that missing side fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'order_type': 'limit',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'side' in error.lower()
    
    def test_invalid_side(self):
        """Test that invalid side fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'hold',
            'order_type': 'limit',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'side' in error.lower()
    
    def test_invalid_order_type(self):
        """Test that invalid order type fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'stop_loss',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'order_type' in error.lower()
    
    def test_zero_quantity(self):
        """Test that zero quantity fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 0,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'quantity' in error.lower()
    
    def test_negative_quantity(self):
        """Test that negative quantity fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': -1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'quantity' in error.lower()
    
    def test_limit_order_missing_price(self):
        """Test that limit order without price fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 1
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'price' in error.lower()
    
    def test_zero_price(self):
        """Test that zero price fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 1,
            'price': 0
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'price' in error.lower()
    
    def test_negative_price(self):
        """Test that negative price fails validation."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 1,
            'price': -100
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'price' in error.lower()
    
    def test_case_insensitive_side(self):
        """Test that side is case-insensitive."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'BUY',
            'order_type': 'limit',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is True
    
    def test_case_insensitive_order_type(self):
        """Test that order_type is case-insensitive."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'LIMIT',
            'quantity': 1,
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is True
    
    def test_string_quantity(self):
        """Test that string quantity is handled."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': '1.5',
            'price': 50000
        }
        is_valid, error = validate_order(order)
        # Should pass since we convert to float
        assert is_valid is True
    
    def test_invalid_quantity_string(self):
        """Test that invalid quantity string fails."""
        order = {
            'symbol': 'BTC-USD',
            'side': 'buy',
            'order_type': 'limit',
            'quantity': 'abc',
            'price': 50000
        }
        is_valid, error = validate_order(order)
        assert is_valid is False
        assert 'quantity' in error.lower()
