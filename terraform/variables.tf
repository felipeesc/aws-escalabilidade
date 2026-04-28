variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "loadsim"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for the app"
  type        = string
  default     = "t3.small"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 10
}

variable "asg_desired" {
  type    = number
  default = 2
}

variable "scale_out_cpu" {
  description = "CPU % that triggers scale-out"
  type        = number
  default     = 60
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "loadsim"
}

variable "db_username" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  description = "RDS master password — set via TF_VAR_db_password or tfvars"
  type        = string
  sensitive   = true
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "app_image" {
  description = "Docker image URI pushed to ECR (or public hub). Leave empty to build from source."
  type        = string
  default     = ""
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "github_org" {
  description = "GitHub org ou usuário — usado na trust policy OIDC do CI"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositório GitHub — usado na trust policy OIDC do CI"
  type        = string
  default     = "aws-escalabilidade"
}

variable "alarm_email" {
  description = "Email para receber alertas CloudWatch via SNS (deixar vazio para não criar assinatura)"
  type        = string
  default     = ""
}
variable "acm_certificate_arn" {
  description = "ARN do certificado ACM para o listener HTTPS do ALB. Deixar vazio para usar HTTP puro (dev/load-test)."
  type        = string
  default     = ""
}
variable "single_nat_gateway" {
  description = "Usar um único NAT Gateway (reduz custo em dev/staging ~$32/mês). Em prod manter false para HA por AZ."
  type        = bool
  default     = false
}
variable "db_multi_az" {
  description = "Habilitar Multi-AZ no RDS. Manter true em prod; false reduz custo em dev/staging."
  type        = bool
  default     = true
}
