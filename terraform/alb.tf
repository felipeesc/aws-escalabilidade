# ── ALB Security Group: allow 80 + 443 inbound ──────────────────────────────
# (security_groups.tf still owns the aws_security_group.alb resource;
#  here we just patch the ingress rules via separate resources so the SG
#  definition stays in one place — or you can inline them there)
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = merge(local.common_tags, { Name = "${var.project}-alb" })
}
resource "aws_lb_target_group" "app" {
  name                 = "${var.project}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "instance"
  deregistration_delay = 30
  health_check {
    path                = "/api/health"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
  tags = merge(local.common_tags, { Name = "${var.project}-tg" })
}
# ── HTTP → HTTPS redirect ────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
# ── HTTPS listener ───────────────────────────────────────────────────────────
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
