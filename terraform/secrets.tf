resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/db-credentials"
  description             = "Credenciais RDS para ${var.project}"
  recovery_window_in_days = 0 # sem janela de recuperação — ambiente de estudo
  tags                    = { Name = "${var.project}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.postgres.address
    port     = tostring(aws_db_instance.postgres.port)
    dbname   = var.db_name
    username = var.db_username
    password = var.db_password
  })
}
