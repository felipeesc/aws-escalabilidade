# ── GitHub Actions OIDC Provider ─────────────────────────────────────────────
# O provider OIDC do GitHub é um singleton por conta AWS.
# Se já existir na conta, importe antes do apply:
#   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
  lifecycle {
    # Evita erro se os thumbprints forem atualizados pela AWS fora do Terraform
    ignore_changes = [thumbprint_list]
  }
}
resource "aws_iam_role" "ci" {
  name = "${var.project}-ci-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "ci" {
  name = "${var.project}-ci-policy"
  role = aws_iam_role.ci.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid    = "ASGRefresh"
        Effect = "Allow"
        Action = [
          "autoscaling:StartInstanceRefresh",
          "autoscaling:DescribeInstanceRefreshes"
        ]
        Resource = "*"
      }
    ]
  })
}
output "ci_role_arn" {
  description = "AWS_ROLE_ARN para configurar no GitHub Secrets"
  value       = aws_iam_role.ci.arn
}
