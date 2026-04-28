output "alb_dns" {
  description = "ALB DNS hostname"
  value       = aws_lb.main.dns_name
}

# Alias exigido pelo fluxo de validacao: terraform output alb_dns_name
output "alb_dns_name" {
  description = "Public ALB endpoint — use directly with k6 and curl"
  value       = aws_lb.main.dns_name
}
# Pronto para usar no k6: k6 run -e BASE_URL=$(terraform output -raw k6_base_url) k6-load-test.js
output "k6_base_url" {
  description = "URL base para o k6 (HTTP quando sem certificado ACM, HTTPS quando com certificado)"
  value       = var.acm_certificate_arn != "" ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}
output "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  value       = "${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}"
  sensitive   = true
}
output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
  sensitive   = true
}
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
output "ecr_repository_url" {
  description = "ECR repository URL para push de imagens"
  value       = aws_ecr_repository.app.repository_url
}
