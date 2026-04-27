#!/bin/bash
# Provisiona o backend remoto (S3 + DynamoDB) e inicializa o Terraform principal.
# Executar uma única vez antes do primeiro `terraform apply`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 1. Provisionando backend (bootstrap)..."
terraform -chdir="$SCRIPT_DIR/bootstrap" init -upgrade
terraform -chdir="$SCRIPT_DIR/bootstrap" apply -auto-approve

BUCKET=$(terraform -chdir="$SCRIPT_DIR/bootstrap" output -raw state_bucket)
TABLE=$(terraform -chdir="$SCRIPT_DIR/bootstrap" output -raw lock_table)
REGION=$(terraform -chdir="$SCRIPT_DIR/bootstrap" output -raw aws_region)

echo ""
echo "==> 2. Inicializando Terraform com backend remoto..."
echo "    bucket=$BUCKET  table=$TABLE  region=$REGION"

terraform -chdir="$SCRIPT_DIR" init -upgrade \
  -backend-config="bucket=$BUCKET" \
  -backend-config="key=loadsim/terraform.tfstate" \
  -backend-config="region=$REGION" \
  -backend-config="dynamodb_table=$TABLE" \
  -backend-config="encrypt=true"

echo ""
echo "==> Backend configurado. Rode: terraform plan"
