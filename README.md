# SOA03-6DAY — EBS 容量・パフォーマンス・データ保護 ＋ 運用監視

AWS Skill Builder ラボ *Managing EBS Volumes: Capacity, Performance, and Data Protection* を題材に、
**ラボに無い「運用監視」の視点**を足して実測検証する Terraform 一式。

## 検証する3つの想定（仮説）

| 仮説 | 要点 | 実測する数値 |
|---|---|---|
| **H1** gp3飽和監視 | gp3に `BurstBalance` は**存在しない**（gp2/st1/sc1専用）。飽和は `VolumeQueueLength` と `(ReadOps+WriteOps)/PERIOD` で見る。EBSメトリクスは**CWエージェント不要**で自動送出 | IOPSが約3000で頭打ち／QueueLength上昇／BurstBalance空 |
| **H2** 変更のイベント監視 | `modify-volume` は即時完了でなく `optimizing`→`completed`。完了は EventBridge `EBS Volume Modification` で駆動。FS拡張は `xfs_growfs` 別途 | 3000→5000 IOPS変更のoptimizing所要時間 |
| **H3** RAID0の整合バックアップ | RAID0は1本損失で全損。個別スナップショットは不整合になりうる→**instance単位（マルチVol）スナップショット**で同一時点整合 | 復元先でRAID0情報ごとデータ整合を確認 |

## 構成

- EC2 `t3.small` ×1（コマンドホスト・SSM接続・**egressのみSG**・IMDSv2必須・`shutdown -h +1440`）
- gp3ボリューム ×2（100GB・暗号化ON・初期3000/125）
- 監視: SNS＋EventBridge（変更検知）＋CloudWatchアラーム（IOPS数式／VolumeQueueLength）
- 負荷生成は **SSM send-command で `localhost`内fio**（インバウンド無し）

> **割愛**: SecondHost（H3の整合性証明は同一ホストの別マウントで足りる）、Windows/IIS等のラボ外要素、
> 高コストなm5.xlarge（ラボの順次500MB/sはt3のEBSバースト帯域上限に当たるため、それ自体を運用示唆として記事化）。

## 使い方

```bash
cd ~/projects/SOA03-06DAY
terraform init
terraform apply            # 課金開始。終わったら必ず destroy
# 通知メールを使う場合: terraform apply -var="notification_email=you@example.com"
terraform output session_manager_url   # ブラウザで開いてコマンドホストへ
```

## 検証Runbook（Phase 3）

`run()` = SSM send-command→`get-command-invocation` のヘルパ（`_lib.sh`）。

```bash
IID=$(terraform output -raw instance_id)
V0=$(terraform output -json data_volume_ids | jq -r '.[0]')
V1=$(terraform output -json data_volume_ids | jq -r '.[1]')

# --- H1: 単一gp3でIOPS上限とQueueLengthを実測 ---
run "$IID" 'sudo mkfs -t xfs /dev/nvme1n1 && sudo mkdir -p /data1 && sudo mount /dev/nvme1n1 /data1'
run "$IID" 'sudo fio --directory=/data1 --ioengine=psync --name t --direct=1 --rw=randrw --bs=16k --numjobs=16 --size=100M --time_based --runtime=240 --group_reporting --norandommap' &
# 走行中に CloudWatch を観測（5分粒度なので数分待つ）
aws cloudwatch get-metric-data ... VolumeReadOps/VolumeWriteOps/VolumeQueueLength
# gp3にBurstBalanceが無いことを確認（空が返る）
aws cloudwatch get-metric-statistics --namespace AWS/EBS --metric-name BurstBalance \
  --dimensions Name=VolumeId,Value=$V0 --statistics Average --period 300 ...

# --- H2: I/O継続中にオンライン変更し、optimizing所要時間＋EventBridgeを観測 ---
aws ec2 modify-volume --volume-id $V0 --size 120 --iops 5000 --throughput 250
aws ec2 describe-volumes-modifications --volume-ids $V0 \
  --query 'VolumesModifications[].{state:ModificationState,prog:Progress}'
run "$IID" 'sudo xfs_growfs /data1 && df -h /data1'   # 変更後にFS拡張

# --- H3: RAID0→instance単位スナップショット→復元→整合確認 ---
run "$IID" 'sudo umount /data1; sudo mdadm --create --verbose /dev/md0 --level=0 --name=MY_RAID --raid-devices=2 /dev/nvme1n1 /dev/nvme2n1'
run "$IID" 'sudo mkfs -t xfs /dev/md0 && sudo mount /dev/md0 /data1 && echo INTEGRITY-$(date +%s) | sudo tee /data1/marker.txt && sudo sha256sum /data1/marker.txt'
aws ec2 create-snapshots --instance-specification InstanceId=$IID,ExcludeBootVolume=true --description Hostsnap
# → スナップショットからボリューム作成→アタッチ→/snapdataにmount→marker.txtのsha256一致を確認

# --- クリーンアップ ---
terraform destroy
# 異常検知器/手動スナップショット等の残骸が無いか describe-* で空確認
```

## ハマりどころ / 設計メモ

- **gp3に `BurstBalance` は無い**。gp2前提のアラームをコピペするとgp3で無言で無効化される（H1の核）。
- **EBSメトリクスは5分粒度が基本** → 飽和検知に固有のラグ。IOPS数式は `PERIOD()` で割って粒度非依存に。
- **`modify-volume` は即時でない**。`optimizing` 中は旧性能。24hに1回制限。完了はEventBridge駆動。
- **変更後 `xfs_growfs` を忘れるとFSは拡張されない**（`df -h` が増えない）。
- **RAID0は1本損失で全損** → integrity優先。複数Vol構成は**instance単位スナップショット**で整合。
- **復元時にタイプ未指定だと既定gp2**（元gp3と性能特性が変わる）。
- WSLは `wsl bash -lic` 必須・`MSYS_NO_PATHCONV=1`・入れ子クォートは `_*.sh` 化。

## 後始末チェック

```bash
terraform destroy
aws ec2 describe-volumes --filters Name=tag:Project,Values=SOA03-6DAY --query 'Volumes[].VolumeId'   # 空
aws ec2 describe-snapshots --owner-ids self --filters Name=description,Values=Hostsnap --query 'Snapshots[].SnapshotId'  # 手動分は手動削除
```
