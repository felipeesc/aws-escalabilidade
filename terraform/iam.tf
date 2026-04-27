resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
# SSM Session Manager — SSH sem key pair exposto
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# ECR read — pra puxar a imagem
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
# CloudWatch Logs — escopo restrito ao log group do projeto
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project}-logs-policy"
  role = aws_iam_role.ec2.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:CreateLogGroup"
      ]
      Resource = [
        "arn:aws:logs:*:*:log-group:/loadsim/app",
        "arn:aws:logs:*:*:log-group:/loadsim/app:*"
      ]
    }]
  })
}
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}
# Acesso restrito ao secret específico do projeto
resource "aws_iam_role_policy" "secrets" {
  name = "${var.project}-secrets-policy"
  role = aws_iam_role.ec2.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db.arn]
    }]
  })
}
