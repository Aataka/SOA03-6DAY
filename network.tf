# 自己完結のためデフォルトVPC/サブネットを利用（検証用の最小構成）
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 先頭サブネットを採用し、そのAZにEBSボリュームを作る（EBSとEC2は同一AZ必須）
data "aws_subnet" "selected" {
  id = tolist(data.aws_subnets.default.ids)[0]
}

# インバウンドを一切開けない（egressのみ）。負荷生成はSSM経由でlocalhostへ。
resource "aws_security_group" "host" {
  name_prefix = "${var.name_prefix}-egress-"
  description = "Egress only - no inbound. Access via SSM Session Manager"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "All outbound (SSM endpoints, dnf, S3)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-egress" }

  lifecycle {
    create_before_destroy = true
  }
}
