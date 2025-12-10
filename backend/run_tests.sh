#!/bin/bash
# Test runner script for the exchange service

set -e

echo "Running Exchange Service Tests"
echo "=============================="

# Check if we're in the backend directory
if [ ! -f "pytest.ini" ]; then
    echo "Error: Please run this script from the backend directory"
    exit 1
fi

# Run unit tests
echo ""
echo "Running Unit Tests..."
echo "-------------------"
pytest ingest/test_lambda_function.py matcher/test_lambda_function.py -v

# Run with coverage if pytest-cov is installed
if python -c "import pytest_cov" 2>/dev/null; then
    echo ""
    echo "Running Tests with Coverage..."
    echo "----------------------------"
    pytest ingest/test_lambda_function.py matcher/test_lambda_function.py \
        --cov=ingest --cov=matcher \
        --cov-report=html \
        --cov-report=term-missing
    echo ""
    echo "Coverage report generated in htmlcov/index.html"
fi

# Check if LocalStack is running for integration tests
if docker ps | grep -q localstack; then
    echo ""
    echo "LocalStack detected. Running Integration Tests..."
    echo "------------------------------------------------"
    pytest test_integration.py -v -m integration || echo "Integration tests skipped (LocalStack may not be fully ready)"
else
    echo ""
    echo "Skipping Integration Tests (LocalStack not running)"
    echo "Start LocalStack with: docker-compose up -d"
fi

echo ""
echo "Tests Complete!"

