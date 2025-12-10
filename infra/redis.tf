# =============================================================================
# ELASTICACHE REDIS
# Cost: cache.t3.micro ~$13/month (1 node, no Multi-AZ)
# Note: Using public subnets for MVP to avoid NAT Gateway costs
# =============================================================================

# Redis Auth Token stored in Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth" {
  name        = "redis-auth-token"
  description = "Redis authentication token for exchange cluster"

  # Generate a random password
  recovery_window_in_days = 0  # For MVP, no recovery window to save costs
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
  })
}

# Generate random password for Redis
resource "random_password" "redis_auth" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"  # Only allowed special characters for ElastiCache
}

# Redis Subnet Group
# Note: Using public subnets for MVP (private subnets would require NAT Gateway = $32/month)
resource "aws_elasticache_subnet_group" "redis_subnet" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Redis Replication Group (supports auth_token)
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "exchange-redis"
  description                = "Redis cluster for exchange with auth"
  engine                     = "redis"
  node_type                  = "cache.t3.micro"  # Smallest instance type
  num_cache_clusters         = 1  # Single node (no Multi-AZ for cost savings)
  parameter_group_name       = "default.redis7"
  engine_version             = "7.0"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet.name
  security_group_ids         = [aws_security_group.redis_sg.id]
  
  # Auth token from Secrets Manager
  auth_token                 = random_password.redis_auth.result
  transit_encryption_enabled = true  # Required for auth_token
  at_rest_encryption_enabled = true

  # Snapshot disabled to save costs
  snapshot_retention_limit = 0
  snapshot_window          = ""

  tags = {
    Name = "exchange-redis"
  }
}

# Outputs
output "redis_endpoint" {
  description = "The DNS endpoint for the Redis cluster"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "The port for the Redis cluster"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_auth_secret_arn" {
  description = "ARN of the Redis auth token secret"
  value       = aws_secretsmanager_secret.redis_auth.arn
  sensitive   = true
}
