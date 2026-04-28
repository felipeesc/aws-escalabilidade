resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = merge(local.common_tags, { Name = "${var.project}-db-subnet-group" })
}
resource "aws_db_instance" "postgres" {
  identifier                   = "${var.project}-postgres"
  engine                       = "postgres"
  engine_version               = "16"
  instance_class               = var.db_instance_class
  allocated_storage            = 20
  max_allocated_storage        = 100
  storage_type                 = "gp3"
  storage_encrypted            = true
  db_name                      = var.db_name
  username                     = var.db_username
  password                     = var.db_password
  db_subnet_group_name         = aws_db_subnet_group.postgres.name
  vpc_security_group_ids       = [aws_security_group.rds.id]
  multi_az                     = var.db_multi_az
  publicly_accessible          = false
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.project}-final-snapshot"
  backup_retention_period      = 7
  backup_window                = "03:00-04:00"
  maintenance_window           = "Mon:04:00-Mon:05:00"
  performance_insights_enabled = true
  tags                         = merge(local.common_tags, { Name = "${var.project}-postgres" })
}
