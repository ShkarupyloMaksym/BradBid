# Terraform Remediation Guide

## Overview
This guide provides step-by-step instructions to resolve two critical Terraform errors:
1. **CloudWatch Log Group Conflict** - ResourceAlreadyExistsException
2. **ElastiCache Configuration Error** - InvalidParameterValue when modifying cluster in replication group

---

## Issue 1: CloudWatch Log Group Conflict

### Problem
Terraform is attempting to create CloudWatch log groups that already exist in AWS but are missing from the Terraform state file. This causes a `ResourceAlreadyExistsException`.

### Root Cause
AWS Lambda automatically creates log groups when functions are first invoked. If these log groups were created before being added to Terraform, they exist in AWS but not in Terraform state.

### Solution: Import Existing Log Groups

#### Step 1: Identify Existing Log Groups
List all log groups that need to be imported:
```powershell
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/Exchange" --query 'logGroups[*].logGroupName' --output table
```

Expected log groups:
- `/aws/lambda/ExchangeIngest`
- `/aws/lambda/ExchangeMatcher`
- `/aws/lambda/ExchangeWSHandler`
- `/aws/lambda/ExchangeTradeBroadcaster`

#### Step 2: Import Log Groups into Terraform State

Run these commands from the `infra` directory:

```powershell
# Import Ingest Lambda log group
terraform import aws_cloudwatch_log_group.ingest_lambda_logs /aws/lambda/ExchangeIngest

# Import Matcher Lambda log group
terraform import aws_cloudwatch_log_group.matcher_lambda_logs /aws/lambda/ExchangeMatcher

# Import WebSocket Handler Lambda log group
terraform import aws_cloudwatch_log_group.ws_handler_logs /aws/lambda/ExchangeWSHandler

# Import Trade Broadcaster Lambda log group
terraform import aws_cloudwatch_log_group.trade_broadcaster_logs /aws/lambda/ExchangeTradeBroadcaster
```

#### Step 3: Verify Import
```powershell
terraform state list | Select-String "cloudwatch_log_group"
```

You should see all four log groups listed.

#### Step 4: Plan and Apply
```powershell
terraform plan
terraform apply
```

---

## Issue 2: ElastiCache Configuration Error

### Problem
Terraform is attempting to modify an ElastiCache cluster that is managed as part of a replication group. This causes an `InvalidParameterValue` error because clusters within replication groups cannot be modified directly.

### Root Cause
The current configuration uses `aws_elasticache_cluster` resource, but if the cluster is part of a replication group (either created manually or by a previous Terraform run), modifications must be made to the replication group, not the individual cluster.

### Solution: Refactor to Use Replication Group

#### Step 1: Check Current ElastiCache Setup

First, verify if a replication group exists:
```powershell
aws elasticache describe-replication-groups --query 'ReplicationGroups[*].[ReplicationGroupId,Status]' --output table
```

If a replication group exists, note its ID. If not, we'll create one.

#### Step 2: Import Existing Replication Group (if exists)

If a replication group already exists (e.g., `exchange-redis-replication-group`):
```powershell
terraform import aws_elasticache_replication_group.redis exchange-redis-replication-group
```

#### Step 3: Update Terraform Configuration

The `redis.tf` file has been refactored to use `aws_elasticache_replication_group` instead of `aws_elasticache_cluster`. The new configuration:
- Uses replication group for better high availability
- Maintains the same cluster ID for backward compatibility
- Updates all references in Lambda and monitoring configurations

#### Step 4: Remove Old Cluster from State (if needed)

If the cluster was previously managed separately:
```powershell
# First, check if it exists in state
terraform state list | Select-String "elasticache_cluster"

# If it exists, remove it (the cluster is now managed by replication group)
terraform state rm aws_elasticache_cluster.redis
```

#### Step 5: Update References

All references to `aws_elasticache_cluster.redis` have been updated to use `aws_elasticache_replication_group.redis`:
- Lambda environment variables (REDIS_HOST)
- CloudWatch dashboard metrics
- Output values

#### Step 6: Plan and Apply
```powershell
terraform plan
# Review the plan carefully - it may show the cluster being replaced
terraform apply
```

**Note:** If the cluster is already part of a replication group, Terraform will detect this and may show a replacement. This is expected behavior.

---

## Complete Remediation Workflow

### Option A: Automated Script (Recommended)

Run the updated import script:
```powershell
cd infra
.\import-resources.ps1
```

This script now includes CloudWatch log group imports.

### Option B: Manual Steps

1. **Import CloudWatch Log Groups:**
   ```powershell
   terraform import aws_cloudwatch_log_group.ingest_lambda_logs /aws/lambda/ExchangeIngest
   terraform import aws_cloudwatch_log_group.matcher_lambda_logs /aws/lambda/ExchangeMatcher
   terraform import aws_cloudwatch_log_group.ws_handler_logs /aws/lambda/ExchangeWSHandler
   terraform import aws_cloudwatch_log_group.trade_broadcaster_logs /aws/lambda/ExchangeTradeBroadcaster
   ```

2. **Check ElastiCache Replication Group:**
   ```powershell
   aws elasticache describe-replication-groups --query 'ReplicationGroups[*].ReplicationGroupId' --output table
   ```

3. **If replication group exists, import it:**
   ```powershell
   terraform import aws_elasticache_replication_group.redis <replication-group-id>
   ```

4. **Remove old cluster from state (if present):**
   ```powershell
   terraform state rm aws_elasticache_cluster.redis
   ```

5. **Plan and Apply:**
   ```powershell
   terraform plan
   terraform apply
   ```

---

## Verification Steps

After remediation, verify everything is working:

1. **Check Terraform State:**
   ```powershell
   terraform state list
   ```

2. **Verify Log Groups:**
   ```powershell
   terraform state show aws_cloudwatch_log_group.ingest_lambda_logs
   ```

3. **Verify ElastiCache:**
   ```powershell
   terraform state show aws_elasticache_replication_group.redis
   ```

4. **Test Terraform Plan:**
   ```powershell
   terraform plan
   ```
   Should show no errors and minimal changes (if any).

---

## Troubleshooting

### If Import Fails for Log Groups
- Verify the log group name exactly matches: `/aws/lambda/<FunctionName>`
- Check AWS region matches your Terraform configuration
- Ensure you have proper AWS credentials configured

### If ElastiCache Import Fails
- Verify the replication group ID exists in AWS
- Check if the cluster is actually part of a replication group
- If no replication group exists, the new configuration will create one

### If Terraform Plan Shows Unexpected Changes
- Review the plan output carefully
- Some changes may be expected (e.g., adding replication group configuration)
- Use `terraform plan -detailed-exitcode` to see specific changes

---

## Additional Notes

- **Backup State File:** Always backup your `terraform.tfstate` file before making changes
- **Test in Non-Prod:** If possible, test these changes in a non-production environment first
- **Documentation:** Keep this guide updated as your infrastructure evolves

---

## Quick Reference: Import Commands

```powershell
# CloudWatch Log Groups
terraform import aws_cloudwatch_log_group.ingest_lambda_logs /aws/lambda/ExchangeIngest
terraform import aws_cloudwatch_log_group.matcher_lambda_logs /aws/lambda/ExchangeMatcher
terraform import aws_cloudwatch_log_group.ws_handler_logs /aws/lambda/ExchangeWSHandler
terraform import aws_cloudwatch_log_group.trade_broadcaster_logs /aws/lambda/ExchangeTradeBroadcaster

# ElastiCache Replication Group (if exists)
terraform import aws_elasticache_replication_group.redis <replication-group-id>
```

