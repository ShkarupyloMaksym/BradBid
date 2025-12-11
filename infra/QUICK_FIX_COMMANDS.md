# Quick Fix Commands - Terraform Errors

## Issue 1: CloudWatch Log Group Conflict

### Import Commands (Run from `infra` directory)

```powershell
terraform import aws_cloudwatch_log_group.ingest_lambda_logs /aws/lambda/ExchangeIngest
terraform import aws_cloudwatch_log_group.matcher_lambda_logs /aws/lambda/ExchangeMatcher
terraform import aws_cloudwatch_log_group.ws_handler_logs /aws/lambda/ExchangeWSHandler
terraform import aws_cloudwatch_log_group.trade_broadcaster_logs /aws/lambda/ExchangeTradeBroadcaster
```

## Issue 2: ElastiCache Configuration Error

### Check if Replication Group Exists
```powershell
aws elasticache describe-replication-groups --query 'ReplicationGroups[*].ReplicationGroupId' --output table
```

### Import Replication Group (if exists)
```powershell
terraform import aws_elasticache_replication_group.redis <replication-group-id>
```

### Remove Old Cluster from State (if needed)
```powershell
terraform state rm aws_elasticache_cluster.redis
```

## Complete Workflow

1. **Run automated import script:**
   ```powershell
   cd infra
   .\import-resources.ps1
   ```

2. **Verify state:**
   ```powershell
   terraform state list
   ```

3. **Plan and apply:**
   ```powershell
   terraform plan
   terraform apply
   ```

## What Changed

- ✅ `redis.tf` - Refactored to use `aws_elasticache_replication_group` instead of `aws_elasticache_cluster`
- ✅ `lambda.tf` - Updated REDIS_HOST to use replication group endpoint
- ✅ `monitoring.tf` - Updated CloudWatch metrics to use ReplicationGroupId
- ✅ `import-resources.ps1` - Added CloudWatch log group imports and replication group detection

For detailed explanations, see `TERRAFORM_REMEDIATION_GUIDE.md`.

