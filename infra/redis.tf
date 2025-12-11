resource "aws_elasticache_subnet_group" "redis_subnet" {
  name       = "redis-subnet-group"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# ElastiCache Replication Group (replaces aws_elasticache_cluster)
# This resource manages Redis clusters that are part of a replication group.
# Clusters within replication groups cannot be modified directly.
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "exchange-redis-replication-group"
  description                = "Redis replication group for exchange order book"
  
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.t3.micro"
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  # Single node configuration (for cost optimization)
  # Set num_cache_clusters to 1 for single node, or 2+ for multi-AZ
  num_cache_clusters         = 1
  
  # Network configuration
  subnet_group_name          = aws_elasticache_subnet_group.redis_subnet.name
  security_group_ids         = [aws_security_group.redis_sg.id]
  
  # Automatic failover disabled for single node (cost optimization)
  automatic_failover_enabled = false
  
  # Backup configuration
  snapshot_retention_limit   = 1
  snapshot_window            = "03:00-05:00"
  
  # Tags
  tags = {
    Name = "Exchange Redis Cache"
  }
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to num_cache_clusters if manually scaled
      num_cache_clusters,
    ]
  }
}

# Output the primary endpoint (configuration endpoint for cluster mode, or primary endpoint for non-cluster mode)
output "redis_endpoint" {
  description = "The DNS endpoint for the Redis replication group"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address != "" ? aws_elasticache_replication_group.redis.configuration_endpoint_address : aws_elasticache_replication_group.redis.primary_endpoint_address
}

# Additional output for primary endpoint address (for single node or non-cluster mode)
output "redis_primary_endpoint" {
  description = "The primary endpoint address for the Redis replication group"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

# Output for port
output "redis_port" {
  description = "The port number for the Redis replication group"
  value       = aws_elasticache_replication_group.redis.port
}
