resource "aws_cloudwatch_log_group" "app" {
  name              = "/loadsim/app"
  retention_in_days = 7
  tags              = merge(local.common_tags, { Name = "${var.project}-app-logs" })
}

resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"
  tags = merge(local.common_tags, { Name = "${var.project}-alarms" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Mais de 10 erros 5xx/min no ALB"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix }
  tags                = merge(local.common_tags, { Name = "${var.project}-alb-5xx" })
}

resource "aws_cloudwatch_metric_alarm" "alb_latency_p99" {
  alarm_name          = "${var.project}-alb-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 1.5
  alarm_description   = "P99 de latência acima de 1.5s por 3 minutos"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = aws_lb.main.arn_suffix }
  tags                = merge(local.common_tags, { Name = "${var.project}-alb-latency" })
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "${var.project}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "CPU média do ASG acima de 85% por 3 minutos"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
  tags                = merge(local.common_tags, { Name = "${var.project}-asg-cpu" })
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU do RDS acima de 80% por 3 minutos"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.id }
  tags                = merge(local.common_tags, { Name = "${var.project}-rds-cpu" })
}

output "sns_alarms_arn" {
  description = "ARN do tópico SNS de alarmes"
  value       = aws_sns_topic.alarms.arn
}
