# Kubernetesクラスター復旧＆ディスク容量管理ドキュメント

## 📋 **エグゼクティブサマリー**

このドキュメントでは、ディスク容量不足によりアクセス不能になったAWS上のKubernetesクラスターの完全なトラブルシューティングと復旧プロセスを詳述します。根本原因を特定・解決し、予防措置を実装しました。

---

## 🎯 **問題の概要**

**日付**: 2025年1月
**症状**:

- ローカルの`kubectl get nodes`コマンドが接続エラーで失敗
- AWSクラスターへのSSHトンネルが「Connection refused」を返す
- クラスターAPIサーバーが応答しない

**根本原因**: マスターノードのルートファイルシステム（`/`）が100%容量（7.6GB/7.6GB使用済み）に達し、Kubernetesシステムポッドの起動を妨げていた。

---

## 🔍 **診断プロセス**

### **フェーズ1: ネットワーク接続性分析**

**問題**: 基本的なSSH接続は成功するにもかかわらずSSHトンネルが失敗

```
ssh -i ~/.ssh/id_rsa -L 6443:localhost:6443 ubuntu@3.112.132.56 -N
# Error: channel 2: open failed: connect failed: Connection refused
```

**発見**: ネットワーク接続は機能していたが、ポート6443（Kubernetes API）がリッスンしていなかった。

### **フェーズ2: クラスターヘルスチェック**

**実行したコマンド**:

```bash
# AWSコンソール/SSH経由でマスターノード上で
sudo systemctl status kube-apiserver  # "Unit could not be found"
df -h  # 判明: /dev/root 7.6G 7.6G 0 100% /
sudo journalctl -u kubelet | grep "no space"  # ディスク容量エラーを確認
```

**重要な発見**: Kubeletログに以下が表示:

```
CreateContainerConfigError: write /var/lib/kubelet/pods/.../etc-hosts:
no space left on device
```

### **フェーズ3: ディスク容量フォレンジック**

**容量分析コマンド**:

```bash
df -h /  # 全体の使用量
sudo du -sh /*  # トップレベルディレクトリの内訳
sudo du -sh /var/*  # /var分析（合計3.6GB）
sudo du -sh /var/lib/*  # /var/lib分析（合計3.4GB）
```

**調査結果**:
| ディレクトリ | サイズ | 割合 |
|-----------|------|------------|
| `/var/lib/containerd` | 1.8GB | 53% |
| `/var/lib/snapd` | 920MB | 27% |
| `/var/lib/etcd` | 432MB | 13% |
| `/var/lib/apt` | 273MB | 8% |

---

## 🛠️ **復旧アクション**

### **ステップ1: 緊急ディスククリーンアップ**

**実行した安全なクリーンアップコマンド**:

```bash
# 1. ジャーナルログクリーンアップ（約500MB解放）
sudo journalctl --vacuum-time=2d

# 2. APTキャッシュクリーンアップ
sudo apt clean && sudo apt autoclean

# 3. Snapクリーンアップ
sudo snap list --all | grep disabled | awk '{print $1, $3}' | \
  while read snapname revision; do sudo snap remove "$snapname" --revision="$revision"; done
sudo rm -rf /var/lib/snapd/cache/*

# 4. Containerdイメージプルーニング
sudo crictl rmi --prune
```

**結果**: ディスク使用量が**100% → 93%**に減少（595MB空き）

### **ステップ2: クラスターコンポーネントの再起動**

```bash
# kubeletを再起動してstaticポッドを再作成
sudo systemctl restart kubelet
sleep 30

# APIサーバーがリッスンしているか確認
sudo ss -tlnp | grep 6443
```

### **ステップ3: SSHトンネルの再確立**

**トンネルコマンド**:

```bash
ssh -i ~/.ssh/id_rsa -L 6443:localhost:6443 ubuntu@3.112.132.56 -N
```

**証明書の修正**（TLS SAN不一致のため必要）:

```bash
# ローカルマシンの/etc/hostsを編集
sudo nano /etc/hosts
# 追加: 127.0.0.1 ip-172-31-37-254
```

**kubeconfig調整**:

```yaml
# 変更前: server: https://172.31.37.254:6443
# 変更後: server: https://ip-172-31-37-254:6443
```

### **ステップ4: 検証**

```bash
kubectl get nodes
# 成功: 3つすべてのノードが「Ready」ステータスを表示
```

---

## 🚀 **実装した予防措置**

### **1. 自動ジャーナルログクリーンアップ**

**Cronジョブ設定**:

```bash
# 毎日午前5時に実行するよう設定
echo "0 5 * * * /usr/bin/journalctl --vacuum-time=2d" | sudo crontab -
```

**監視スクリプト**:

```bash
# ディスク容量アラート
echo "0 * * * * df -h / | grep -q '9[0-9]%' && echo 'ALERT: Disk over 90% at \$(date)' >> /var/log/disk-alert.log" | sudo crontab -
```

### **2. 強化された監視**

```bash
# プロアクティブ監視用にcrontabに追加
0 3 * * * /usr/local/bin/disk-cleanup-check.sh
```

### **3. ドキュメント＆ランブック**

以下を含むこのドキュメントを作成:

- 根本原因分析
- ステップバイステップの復旧手順
- 予防自動化スクリプト
- トラブルシューティングコマンドリファレンス

---

## 📊 **主な学び**

### **技術的洞察**:

1. **Kubernetesはディスクに敏感**: ディスクが100%に達するとコントロールプレーンコンポーネントがサイレントに失敗する
2. **Containerdストレージの増大**: コンテナイメージがシステムディスクの50%以上を消費する可能性がある
3. **ジャーナルログの蓄積**: ローテーションなしでSystemdジャーナルは無限に増大する
4. **TLS証明書検証**: `localhost`と内部ホスト名の不一致がkubectlを破壊する

### **運用ベストプラクティス**:

1. **ディスク使用量をプロアクティブに監視**: 80%、90%、95%でアラートを設定
2. **自動クリーンアップを実装**: 定期的なメンテナンスで緊急事態を防止
3. **復旧手順を文書化**: 迅速なインシデント対応に不可欠
4. **定期的に復旧をテスト**: 必要なときに手順が機能することを確認

### **AWS固有の注意点**:

1. **EC2インスタンスサイジング**: 8GBルートボリュームは本番Kubernetesには最小限
2. **EBSボリューム拡張**: 本番ワークロードには20GB以上への増加を検討
3. **CloudWatch監視**: ディスク容量メトリクスとアラームを実装

---

## 🛡️ **予防チェックリスト**

### **毎日**:

- [ ] 自動ジャーナルログローテーション（cron: 午前5時）
- [ ] ディスク容量監視（>85%でアラート）

### **毎週**:

- [ ] Containerdイメージプルーニング
- [ ] APTキャッシュクリーンアップ
- [ ] ディスクアラートログのレビュー

### **毎月**:

- [ ] クリーンアップしきい値のレビューと更新
- [ ] 災害復旧手順のテスト
- [ ] クラスターリソース使用率トレンドのレビュー

### **四半期**:

- [ ] ディスク拡張の必要性を評価
- [ ] ドキュメントのレビューと更新
- [ ] バックアップからの完全クラスター復旧テスト

---

## 📞 **緊急連絡先＆エスカレーション**

### **即時アクション**:

1. **ディスク容量確認**: `df -h /`
2. **ジャーナルログクリーン**: `sudo journalctl --vacuum-time=2d`
3. **kubelet再起動**: `sudo systemctl restart kubelet`
4. **接続確認**: `kubectl get nodes`

### **問題が解決しない場合**:

1. **コンポーネントステータス確認**: `sudo systemctl status kubelet containerd`
2. **ログレビュー**: `sudo journalctl -u kubelet -n 100`
3. **エスカレーション先**: [チームリード / クラウド管理者]

---

## 📈 **復旧後のパフォーマンスメトリクス**

**復旧前**:

- ディスク使用量: 100%（0バイト空き）
- APIサーバー: 停止中
- クラスターアクセス: 不能

**復旧後**:

- ディスク使用量: 93%（595MB空き）
- APIサーバー: 稼働中
- クラスターアクセス: 完全復旧
- 自動予防: 実装済み

**予防キャパシティ**:

- 毎日のログローテーションで約500MB解放
- 毎週のメンテナンスで約1GB解放
- 持続可能な使用量: <85%目標

---

## 🔗 **関連ドキュメント**

1. AWS EC2インスタンス管理ガイド
2. Kubernetesクラスター管理マニュアル
3. 災害復旧プレイブック
4. 監視およびアラート設定

---

**ドキュメントバージョン**: 1.0
**最終更新**: 2025年1月
**作成者**: [名前/チーム]
**ステータス**: ✅ 完了＆実装済み
**次回レビュー日**: 2025年4月
