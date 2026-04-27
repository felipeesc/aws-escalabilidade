output "alb_dns" {
  description = "ALB DNS — use como BASE_URL no k6"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  value       = "${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}"
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
  sensitive   = true
}

output "vpc_id" {
  value = aws_vpc.main.id
}
