# PowerShell script to import existing AWS resources into Terraform state
# Run this script from the infra directory: .\import-resources.ps1

Write-Host "Importing existing AWS resources into Terraform state..." -ForegroundColor Green

# Get AWS region (default to eu-central-1)
$region = "eu-central-1"
if ($env:AWS_REGION) {
    $region = $env:AWS_REGION
}

# Get AWS account ID
$accountId = (aws sts get-caller-identity --query Account --output text)
if (-not $accountId) {
    Write-Host "Error: Could not get AWS account ID. Make sure AWS CLI is configured." -ForegroundColor Red
    exit 1
}

Write-Host "AWS Account ID: $accountId" -ForegroundColor Cyan
Write-Host "AWS Region: $region" -ForegroundColor Cyan
Write-Host ""

# Import DynamoDB Tables
Write-Host "Importing DynamoDB tables..." -ForegroundColor Yellow
terraform import aws_dynamodb_table.orders Orders
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Orders table imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import Orders table" -ForegroundColor Red
}

terraform import aws_dynamodb_table.trades Trades
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Trades table imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import Trades table" -ForegroundColor Red
}

# Import SQS Queues
Write-Host "Importing SQS queues..." -ForegroundColor Yellow
$ordersQueueUrl = "https://sqs.$region.amazonaws.com/$accountId/orders.fifo"
terraform import aws_sqs_queue.orders_queue $ordersQueueUrl
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ orders.fifo queue imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import orders.fifo queue" -ForegroundColor Red
}

$tradesQueueUrl = "https://sqs.$region.amazonaws.com/$accountId/trades.fifo"
terraform import aws_sqs_queue.trades_queue $tradesQueueUrl
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ trades.fifo queue imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import trades.fifo queue" -ForegroundColor Red
}

# Import IAM Role
Write-Host "Importing IAM role..." -ForegroundColor Yellow
terraform import aws_iam_role.lambda_role exchange_lambda_role
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ exchange_lambda_role imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import exchange_lambda_role" -ForegroundColor Red
}

# Import ElastiCache Subnet Group
Write-Host "Importing ElastiCache subnet group..." -ForegroundColor Yellow
terraform import aws_elasticache_subnet_group.redis_subnet redis-subnet-group
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ redis-subnet-group imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import redis-subnet-group" -ForegroundColor Red
}

# Import CloudWatch Log Groups
Write-Host "Importing CloudWatch log groups..." -ForegroundColor Yellow
terraform import aws_cloudwatch_log_group.ingest_lambda_logs /aws/lambda/ExchangeIngest
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ExchangeIngest log group imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import ExchangeIngest log group (may not exist yet)" -ForegroundColor Yellow
}

terraform import aws_cloudwatch_log_group.matcher_lambda_logs /aws/lambda/ExchangeMatcher
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ExchangeMatcher log group imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import ExchangeMatcher log group (may not exist yet)" -ForegroundColor Yellow
}

terraform import aws_cloudwatch_log_group.ws_handler_logs /aws/lambda/ExchangeWSHandler
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ExchangeWSHandler log group imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import ExchangeWSHandler log group (may not exist yet)" -ForegroundColor Yellow
}

terraform import aws_cloudwatch_log_group.trade_broadcaster_logs /aws/lambda/ExchangeTradeBroadcaster
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ExchangeTradeBroadcaster log group imported" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to import ExchangeTradeBroadcaster log group (may not exist yet)" -ForegroundColor Yellow
}

# Check for ElastiCache Replication Group
Write-Host "Checking for ElastiCache replication group..." -ForegroundColor Yellow
$replicationGroups = aws elasticache describe-replication-groups --query 'ReplicationGroups[*].ReplicationGroupId' --output text 2>$null
if ($replicationGroups) {
    $rgId = $replicationGroups.Split("`n")[0].Trim()
    Write-Host "  Found replication group: $rgId" -ForegroundColor Cyan
    Write-Host "  Attempting to import..." -ForegroundColor Yellow
    terraform import aws_elasticache_replication_group.redis $rgId
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Replication group imported" -ForegroundColor Green
        Write-Host "  Note: You may need to remove the old cluster from state:" -ForegroundColor Yellow
        Write-Host "    terraform state rm aws_elasticache_cluster.redis" -ForegroundColor Yellow
    } else {
        Write-Host "  ✗ Failed to import replication group" -ForegroundColor Red
    }
} else {
    Write-Host "  No existing replication group found. Terraform will create one." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Import process completed!" -ForegroundColor Green
Write-Host "Note: If any imports failed, you may need to check the resource names or delete and recreate them." -ForegroundColor Yellow
Write-Host "See TERRAFORM_REMEDIATION_GUIDE.md for detailed troubleshooting steps." -ForegroundColor Cyan

