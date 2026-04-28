#!/bin/bash
# Redireciona toda saida para /var/log/user-data.log e console cloud-init
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
set -euo pipefail
# Trap: loga a linha exata de qualquer falha
trap 'echo "[ERROR] user-data falhou na linha $LINENO (exit $?)" >&2' ERR
echo "[INFO] === Inicio do user-data: $(date -u) ==="
# ---------------------------------------------------------------------------
# 1. Validacao: app_image nao pode ser vazio
# ---------------------------------------------------------------------------
APP_IMAGE="${app_image}"
if [[ -z "$APP_IMAGE" ]]; then
  echo "[ERROR] app_image esta vazio. Defina app_image no terraform.tfvars antes de aplicar."
  exit 1
fi
# ---------------------------------------------------------------------------
# 2. Instalar dependencias
# ---------------------------------------------------------------------------
echo "[INFO] Instalando docker e jq..."
dnf install -y docker jq
systemctl enable --now docker
usermod -aG docker ec2-user
echo "[INFO] Docker: $(docker --version)"
# ---------------------------------------------------------------------------
# 3. Metadados via IMDSv2
# ---------------------------------------------------------------------------
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
echo "[INFO] region=$REGION instance=$INSTANCE_ID"
# ---------------------------------------------------------------------------
# 4. Buscar credenciais do Secrets Manager
# ---------------------------------------------------------------------------
echo "[INFO] Buscando secret: ${secret_arn}"
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
echo "[INFO] DB_HOST=$DB_HOST DB_PORT=$DB_PORT DB_NAME=$DB_NAME"
# ---------------------------------------------------------------------------
# 5. Login no ECR (se imagem for privada)
# ---------------------------------------------------------------------------
if [[ "$APP_IMAGE" == *".dkr.ecr."* ]]; then
  ECR_REGISTRY=$(echo "$APP_IMAGE" | cut -d/ -f1)
  echo "[INFO] Login ECR: $ECR_REGISTRY"
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
  echo "[INFO] Login ECR: OK"
fi
# ---------------------------------------------------------------------------
# 6. Subir container
# ---------------------------------------------------------------------------
echo "[INFO] Iniciando container: $APP_IMAGE"
docker run -d \
  --name loadsim \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  --log-driver=awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group="/loadsim/app" \
  --log-opt awslogs-stream="$INSTANCE_ID" \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASS="$DB_PASS" \
  -e REDIS_HOST="${redis_host}" \
  -e REDIS_PORT="${redis_port}" \
  -e REDIS_SSL=true \
  -e PORT="${app_port}" \
  "$APP_IMAGE"
echo "[INFO] Container iniciado. Aguardando app ficar saudavel..."
# ---------------------------------------------------------------------------
# 7. Health check local (nao bloqueia — apenas loga progresso)
# ---------------------------------------------------------------------------
for i in $(seq 1 24); do
  sleep 15
  HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" \
    "http://localhost:${app_port}/api/health" 2>/dev/null || echo "000")
  echo "[INFO] Health check $i/24 ($((i * 15))s): HTTP $HTTP_CODE"
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "[INFO] App saudavel!"
    break
  fi
done
echo "[INFO] === Fim do user-data: $(date -u) ==="
echo "[INFO] Diagnostico via SSM:"
echo "[INFO]   docker ps"
echo "[INFO]   docker logs loadsim --tail 50"
echo "[INFO]   curl http://localhost:${app_port}/api/health"
