variable "region" {
  description = "デプロイ先リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "name_prefix" {
  description = "リソース名のプレフィックス（再apply衝突回避）"
  type        = string
  default     = "soa03-6day"
}

variable "instance_type" {
  description = "コマンドホストのインスタンスタイプ。H1/H3はt3のEBSバースト帯域内で実証可能"
  type        = string
  default     = "t3.small"
}

variable "data_volume_size" {
  description = "検証用gp3ボリュームの初期サイズ(GiB)。H2でCLIから120へオンライン変更する"
  type        = number
  default     = 100
}

variable "notification_email" {
  description = "SNS通知先メール。空なら購読を作らない（確認クリックは手動のため）"
  type        = string
  default     = ""
}

variable "auto_stop_minutes" {
  description = "user_dataでの自動停止までの分数（destroy忘れ課金の頭打ち・stopでありterminateではない）"
  type        = number
  default     = 1440
}
