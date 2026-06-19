# =====================================================================
# 「足した視点」＝ラボに無い運用監視。EBSはCWエージェント不要で
# AWS/EBS 名前空間にメトリクスを自動送出する（H1）。変更はイベント駆動（H2）。
# =====================================================================

# --- SNS（通知先）---
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-ebs-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge / CloudWatch から SNS への publish を許可
data "aws_iam_policy_document" "sns_publish" {
  statement {
    sid       = "AllowEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
  statement {
    sid       = "AllowCloudWatchAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_publish.json
}

# --- H2: EBS ボリューム変更イベント（optimizing/completed/failed）→ SNS ---
resource "aws_cloudwatch_event_rule" "ebs_modification" {
  name        = "${var.name_prefix}-ebs-volume-modification"
  description = "EBS ボリュームのオンライン変更を捕捉（modify-volume は即時完了ではない）"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EBS Volume Modification"]
  })
}

resource "aws_cloudwatch_event_target" "ebs_modification_sns" {
  rule      = aws_cloudwatch_event_rule.ebs_modification.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn

  # メールを読みやすく整形（パスが取れなければ null になるだけで失敗しない）
  input_transformer {
    input_paths = {
      result = "$.detail.result"
      volume = "$.detail.source"
      event  = "$.detail.event"
      time   = "$.time"
    }
    input_template = "\"EBS Volume Modification: <event> result=<result> volume=<volume> at <time>\""
  }
}

# --- H1: gp3 の IOPS 飽和を「数式」で検知（ReadOps+WriteOps を期間で割る）---
# PERIOD() を使い、EBSメトリクスが 60s/300s どちらの粒度でも IOPS に正規化する。
resource "aws_cloudwatch_metric_alarm" "iops_saturation" {
  count               = 2
  alarm_name          = "${var.name_prefix}-vol${count.index}-iops-saturation"
  alarm_description   = "gp3のプロビジョンドIOPS上限(3000)へ接近＝飽和の直接指標"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 2700 # 3000 の 90%
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "iops"
    expression  = "(reads + writes) / PERIOD(reads)"
    label       = "Total IOPS"
    return_data = true
  }
  metric_query {
    id = "reads"
    metric {
      namespace   = "AWS/EBS"
      metric_name = "VolumeReadOps"
      dimensions  = { VolumeId = aws_ebs_volume.data[count.index].id }
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    id = "writes"
    metric {
      namespace   = "AWS/EBS"
      metric_name = "VolumeWriteOps"
      dimensions  = { VolumeId = aws_ebs_volume.data[count.index].id }
      period      = 300
      stat        = "Sum"
    }
  }
}

# --- H1: VolumeQueueLength（飽和の間接指標。gp3に BurstBalance は存在しない）---
resource "aws_cloudwatch_metric_alarm" "queue_length" {
  count               = 2
  alarm_name          = "${var.name_prefix}-vol${count.index}-queue-length"
  alarm_description   = "I/O待ち行列が継続的に高い＝飽和の兆候（gp3の飽和監視の主役）"
  namespace           = "AWS/EBS"
  metric_name         = "VolumeQueueLength"
  dimensions          = { VolumeId = aws_ebs_volume.data[count.index].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 4
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
