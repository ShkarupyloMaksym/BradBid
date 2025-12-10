#!/bin/bash
# LocalStack Setup Script (Krок 12)
# Creates AWS resources in LocalStack for local development

set -e

AWS_ENDPOINT="http://localhost:4566"
REGION="eu-central-1"

echo "Setting up LocalStack resources..."

# Create SQS FIFO queues
echo "Creating SQS queues..."
aws --endpoint-url=$AWS_ENDPOINT sqs create-queue \
    --queue-name orders.fifo \
    --attributes FifoQueue=true,ContentBasedDeduplication=true \
    --region $REGION

aws --endpoint-url=$AWS_ENDPOINT sqs create-queue \
    --queue-name trades.fifo \
    --attributes FifoQueue=true,ContentBasedDeduplication=true \
    --region $REGION

# Create DynamoDB tables
echo "Creating DynamoDB tables..."
aws --endpoint-url=$AWS_ENDPOINT dynamodb create-table \
    --table-name Orders \
    --attribute-definitions AttributeName=OrderId,AttributeType=S \
    --key-schema AttributeName=OrderId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

aws --endpoint-url=$AWS_ENDPOINT dynamodb create-table \
    --table-name Trades \
    --attribute-definitions AttributeName=TradeId,AttributeType=S \
    --key-schema AttributeName=TradeId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

aws --endpoint-url=$AWS_ENDPOINT dynamodb create-table \
    --table-name WSConnections \
    --attribute-definitions AttributeName=ConnectionId,AttributeType=S \
    --key-schema AttributeName=ConnectionId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

# Create S3 buckets
echo "Creating S3 buckets..."
aws --endpoint-url=$AWS_ENDPOINT s3 mb s3://exchange-analytics-local --region $REGION
aws --endpoint-url=$AWS_ENDPOINT s3 mb s3://exchange-spa-local --region $REGION

echo "LocalStack setup complete!"
echo ""
echo "Queue URLs:"
aws --endpoint-url=$AWS_ENDPOINT sqs list-queues --region $REGION

echo ""
echo "DynamoDB Tables:"
aws --endpoint-url=$AWS_ENDPOINT dynamodb list-tables --region $REGION

echo ""
echo "S3 Buckets:"
aws --endpoint-url=$AWS_ENDPOINT s3 ls
