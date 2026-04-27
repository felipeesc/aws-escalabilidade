#!/bin/bash
set -euo pipefail

# instala Docker e jq no AL2023
dnf install -y docker jq
systemctl enable --now docker
usermod -aG docker ec2-user

# Busca região via metadados da instância — sem hardcode
REGION=$(curl -s -m 5 http://169.254.169.254/latest/meta-data/placement/region)

# Busca credenciais do Secrets Manager usando a IAM Role da instância
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "$REGION" \
  --query SecretString \
  --output text)

DB_HOST=$(echo "$SECRET" | jq -r '.host')
DB_PORT=$(echo "$SECRET" | jq -r '.port')
DB_NAME=$(echo "$SECRET" | jq -r '.dbname')
DB_USER=$(echo "$SECRET" | jq -r '.username')
DB_PASS=$(echo "$SECRET" | jq -r '.password')

# login no ECR se a imagem for privada
if [[ "${app_image}" == *".dkr.ecr."* ]]; then
  ECR_REGISTRY=$(echo "${app_image}" | cut -d/ -f1)
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
fi

docker run -d \
  --name loadsim \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASS="$DB_PASS" \
  -e REDIS_HOST="${redis_host}" \
  -e REDIS_PORT="${redis_port}" \
  -e REDIS_SSL=true \
  -e DDL_AUTO=validate \
  -e PORT="${app_port}" \
  "${app_image}"
