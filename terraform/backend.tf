# Backend configurado via init.sh após rodar o bootstrap.
# Não editar manualmente — ver README seção "Configurar backend remoto".
terraform {
  backend "s3" {}
}
