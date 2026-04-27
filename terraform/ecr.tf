resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = local.common_tags
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remover imagens sem tag após 1 dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Manter apenas as 10 imagens tagged mais recentes"
        selection = {
          tagStatus      = "tagged"
          tagPrefixList  = ["v", "sha-", "latest"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
