output "instance_id" {
  description = "コマンドホストのインスタンスID"
  value       = aws_instance.host.id
}

output "session_manager_url" {
  description = "Session Manager でコマンドホストに接続するURL"
  value       = "https://${var.region}.console.aws.amazon.com/systems-manager/session-manager/${aws_instance.host.id}?region=${var.region}"
}

output "data_volume_ids" {
  description = "検証用gp3ボリュームのID（firstvol, secondvol）"
  value       = aws_ebs_volume.data[*].id
}

output "availability_zone" {
  description = "EC2とEBSを配置したAZ"
  value       = data.aws_subnet.selected.availability_zone
}

output "sns_topic_arn" {
  description = "アラート/イベント通知先SNSトピックARN"
  value       = aws_sns_topic.alerts.arn
}
