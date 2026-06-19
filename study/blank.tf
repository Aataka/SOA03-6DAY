# 白紙再現テスト用スケルトン（最終テスト）。値・属性をコメントだけ残し中身は自分で埋める。
# 答え合わせは compute.tf / monitoring.tf との diff で。穴は本番＝自分のdiffから作り直す。

# --- 検証用 gp3 ボリューム 2 本（初期 3000 IOPS / 125 MB/s）---
# ヒント: H2でCLIからオンライン変更するので ignore_changes が要る
resource "aws_ebs_volume" "data" {
  count = 2
  # availability_zone = ?  （EC2と同一AZ必須。どこから取る？）
  # size              = ?
  # type              = ?
  # iops              = ?
  # throughput        = ?
  # encrypted         = ?
  # lifecycle { ignore_changes = [ ? ] }   ← なぜ必要？
}

# --- H1: gp3 IOPS 飽和アラーム（数式）---
# ヒント: 固定の数で割らない。粒度非依存にする関数は？
resource "aws_cloudwatch_metric_alarm" "iops_saturation" {
  # comparison_operator = ?
  # threshold           = ?   （3000の何%？）
  # metric_query { id="iops"  expression = "( ? + ? ) / ?()" ... }
  # metric_query { id="reads" metric { namespace=? metric_name=? stat=? } }
  # metric_query { id="writes" ... }
}

# --- H1: 飽和の間接指標（gp3に存在しないメトリクスは使わない）---
resource "aws_cloudwatch_metric_alarm" "queue_length" {
  # metric_name = ?   （BurstBalanceは×。gp3で使えるのは？）
}

# --- H2: ボリューム変更イベント → SNS ---
# ヒント: modify-volume は即時完了ではない。何のイベントを拾う？
resource "aws_cloudwatch_event_rule" "ebs_modification" {
  # event_pattern = jsonencode({ source = [ ? ], detail-type = [ ? ] })
}
