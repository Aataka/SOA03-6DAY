data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- IAM: SSM Session Manager / send-command 用（SSH鍵なし）---
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  name_prefix        = "${var.name_prefix}-ssm-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  name_prefix = "${var.name_prefix}-"
  role        = aws_iam_role.host.name
}

# --- コマンドホスト（ラボの FirstHost 相当）---
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -x
    # ベンチ(fio)/RAID(mdadm)/画像変換(ImageMagick)。いずれも非致命にしてSSM起動を止めない
    dnf install -y fio mdadm ImageMagick || echo "WARN: package install failed"
    # destroy忘れの課金頭打ち：N分後に停止（terminateではなくstop）
    shutdown -h +${var.auto_stop_minutes} || echo "WARN: shutdown schedule failed"
  EOF
}

resource "aws_instance" "host" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.host.id]
  iam_instance_profile        = aws_iam_instance_profile.host.name
  associate_public_ip_address = true
  user_data                   = local.user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 必須
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.name_prefix}-CommandHost" }
}

# --- 検証用 gp3 ボリューム 2 本（初期 3000 IOPS / 125 MB/s）---
# H2 ではこれらを CLI から 5000 IOPS / 250 MB/s / 120GiB へ「オンライン変更」する。
# 変更後に terraform が初期値へ戻そうとしないよう ignore_changes を付与。
resource "aws_ebs_volume" "data" {
  count             = 2
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = { Name = "${var.name_prefix}-${count.index == 0 ? "firstvol" : "secondvol"}" }

  lifecycle {
    ignore_changes = [iops, throughput, size]
  }
}

resource "aws_volume_attachment" "data" {
  count        = 2
  device_name  = count.index == 0 ? "/dev/sdf" : "/dev/sdg"
  volume_id    = aws_ebs_volume.data[count.index].id
  instance_id  = aws_instance.host.id
  force_detach = true # I/O中でもdestroyを止めない（検証用途）
}
