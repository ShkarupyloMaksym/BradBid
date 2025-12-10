# Deployment Guide - Bidding Exchange Service MVP

## Overview

This guide covers the deployment of the Bidding Exchange Service MVP on AWS using Terraform.

## Architecture Summary

### Components

1. **API Gateway** - REST API endpoint for order ingestion
2. **Ingest Lambda** - Validates and ingests orders to Kinesis
3. **Kinesis Data Streams** - `KDS_Orders` and `KDS_Trades` (1 shard each)
4. **Matcher Lambda** - Processes orders, maintains order book in Redis, matches trades
5. **ElastiCache Redis** - Order book storage (cache.t3.micro, single node)
6. **DynamoDB** - `Orders` and `Trades` tables (On-Demand billing)
7. **S3 Data Lake** - Raw data storage with lifecycle policies
8. **Kinesis Firehose** - Delivers data from KDS to S3
9. **AWS Glue** - Data catalog crawlers
10. **Athena** - Query engine for analytics
11. **CloudWatch** - Monitoring and dashboards
12. **X-Ray** - Distributed tracing

## Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.0
- AWS CLI configured
- Python 3.11+ (for Lambda functions)

## Deployment Steps

### 1. Initialize Terraform

```bash
cd infra
terraform init
```

### 2. Review Configuration

Edit `provider.tf` to set your AWS region (default: `eu-central-1`):

```hcl
variable "aws_region" {
  description = "AWS Region to deploy resources"
  default     = "us-east-1"  # Change as needed
}
```

### 3. Plan Deployment

```bash
terraform plan
```

Review the plan to ensure all resources are correct.

### 4. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

### 5. Get Outputs

After deployment, get important outputs:

```bash
terraform output
```

Key outputs:
- `api_gateway_url` - API endpoint for submitting orders
- `redis_endpoint` - Redis cluster endpoint
- `s3_data_lake_bucket_name` - S3 bucket for data lake
- `cloudwatch_dashboard_url` - CloudWatch dashboard URL

## Testing the Deployment

### 1. Submit a Test Order

```bash
API_URL=$(terraform output -raw api_gateway_url)

curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "orderId": "test-001",
    "symbol": "BTCUSD",
    "side": "BUY",
    "quantity": 1.5,
    "price": 50000.0
  }'
```

### 2. Check CloudWatch Logs

```bash
# Ingest Lambda logs
aws logs tail /aws/lambda/ExchangeIngest --follow

# Matcher Lambda logs
aws logs tail /aws/lambda/ExchangeMatcher --follow
```

### 3. Query DynamoDB

```bash
# Check orders
aws dynamodb scan --table-name Orders --limit 10

# Check trades
aws dynamodb scan --table-name Trades --limit 10
```

### 4. View CloudWatch Dashboard

Open the dashboard URL from Terraform outputs to monitor:
- Kinesis iterator age (lag)
- Lambda errors and duration
- DynamoDB consumed capacity
- Redis CPU utilization

## Running Glue Crawlers

After data starts flowing to S3, run the Glue crawlers to build the data catalog:

```bash
# Start orders crawler
aws glue start-crawler --name orders-crawler

# Start trades crawler
aws glue start-crawler --name trades-crawler

# Check crawler status
aws glue get-crawler --name orders-crawler
```

## Querying with Athena

Once crawlers complete, query the data:

```sql
-- Query orders
SELECT * FROM exchange_data_lake.orders
WHERE year = '2024' AND month = '01'
LIMIT 100;

-- Query trades
SELECT * FROM exchange_data_lake.trades
WHERE year = '2024' AND month = '01'
LIMIT 100;

-- Aggregate trades by symbol
SELECT 
  symbol,
  COUNT(*) as trade_count,
  SUM(quantity) as total_quantity,
  AVG(price) as avg_price
FROM exchange_data_lake.trades
WHERE year = '2024' AND month = '01'
GROUP BY symbol;
```

## Cost Optimization

### Current Configuration

- **Kinesis**: 1 shard per stream (~$11/month each = $22/month)
- **Redis**: cache.t3.micro, single node (~$13/month)
- **DynamoDB**: On-Demand billing (pay per request)
- **Lambda**: Free tier: 1M requests/month
- **S3**: Pay per GB stored (with lifecycle policies)
- **Glue**: Pay per DPU-hour when crawlers run
- **Athena**: $5 per TB scanned

### Estimated Monthly Cost

- Kinesis: ~$22
- Redis: ~$13
- DynamoDB: ~$5-10 (depending on usage)
- Lambda: $0 (within free tier)
- S3: ~$1-5 (depending on data volume)
- Glue: ~$1-2 (occasional crawler runs)
- Athena: Pay per query
- **Total: ~$40-50/month** (excluding data transfer)

### Cost Reduction Tips

1. **Reduce Kinesis shards** if throughput is low (already at minimum: 1)
2. **Use smaller Redis instance** (already at minimum: cache.t3.micro)
3. **Enable S3 lifecycle policies** (already configured)
4. **Schedule Glue crawlers** to run less frequently
5. **Use Athena result caching** to reduce scan costs

## Troubleshooting

### Lambda Timeout Errors

If Matcher Lambda times out:
- Increase timeout in `lambda.tf` (currently 60 seconds)
- Check Redis connection and performance
- Review CloudWatch logs for bottlenecks

### Kinesis Iterator Age High

If iterator age is high:
- Check Matcher Lambda errors
- Verify Lambda event source mapping is active
- Consider increasing Lambda concurrency

### Redis Connection Errors

If Redis connection fails:
- Verify security group allows Lambda access
- Check Redis endpoint in Lambda environment variables
- Verify Secrets Manager secret contains correct auth token

### DynamoDB Throttling

If DynamoDB throttles:
- On-Demand mode should auto-scale, but check for hot partitions
- Review CloudWatch metrics for throttled requests
- Consider adding GSI if query patterns require it

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data including:
- DynamoDB tables and data
- S3 buckets and data
- Kinesis streams and data
- All other resources

## Security Notes

1. **Redis is in public subnets** - For production, move to private subnets with NAT Gateway
2. **API Gateway has no authentication** - Add API keys or Cognito for production
3. **Secrets Manager** - Redis auth token is stored securely
4. **IAM roles** - Use least-privilege policies (already configured)

## Next Steps

1. Add API Gateway authentication (API keys or Cognito)
2. Move Redis to private subnets (requires NAT Gateway)
3. Add WebSocket API for real-time trade notifications
4. Implement order cancellation
5. Add more comprehensive error handling and DLQ
6. Set up CI/CD pipeline
7. Add integration tests

