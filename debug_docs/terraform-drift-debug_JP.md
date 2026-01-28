# Terraform × Kubernetes ドリフトデバッグストーリー

## 背景

このプロジェクトは、AWS EC2インスタンス上で動作する**セルフホストGitHub Actionsランナー**を介して実行される**Terraform**でKubernetesクラスターを管理しています。

クラスター自体には、以前作成されたリソース（Deployment、Service、RBACオブジェクト）が既に含まれていました。Terraformは後から導入され、これらのリソースを完全に管理し、CI/CDを通じて望ましい状態を強制するようになりました。

---

## 最初の問題: Terraform Applyが繰り返し失敗

TerraformコードをGitHubにプッシュした後、CIパイプラインが以下のようなエラーで繰り返し失敗しました：

```
deployments.apps "marketplace" already exists
services "recommendations" already exists
namespaces "tfdrift-operator-system" already exists
```

Terraformは一貫して**既にクラスターに存在するリソースを作成しよう**としていました。

---

## 根本原因 #1: CIでTerraformステートが空だった

Terraformコマンド（`import`、`plan`、`apply`）はある時点でセルフホストランナー上で手動実行されましたが、**Terraformステートはci実行間で永続化されていませんでした**。

重要な事実：

- Terraformは開発者マシン上で**ローカル実行されたことがなかった**
- セルフホストランナーは**エフェメラル（一時的）**
- 各GitHub Actions実行は以下で開始:
  - フレッシュなチェックアウト
  - **空のTerraformステート**

- Kubernetesには既にリソースが存在

そのため、すべてのCI実行は以下のように動作：

> 「ステートが空 → すべて作成する必要がある」

これは即座に現実と競合しました。

---

## 失敗した試み: 手動の`terraform import`

ランナー上で手動で`terraform import`を実行しても**CIは修正されませんでした**。なぜなら：

- GitHub Actionsは**クリーンな環境**で実行される
- インポートされたステートは後続のCI実行で**利用できなかった**
- CIは`terraform import`を実行しなかった

これにより、Terraformは既存リソースの再作成を繰り返し試みる結果になりました。

---

## 根本原因 #2: CIパイプラインにステート調整がなかった

元のワークフロー：

```yaml
terraform init
terraform validate
terraform plan
terraform apply
```

には**ライブKubernetesステートをTerraformステートに調整するステップがありませんでした**。

Terraformは技術的には正しかった — 単にそれらのリソースが既に存在することを知らなかっただけです。

---

## 解決策: CI内でTerraformステートをブートストラップ

これを修正するために、**Terraformインポートステップを直接CIワークフローに追加しました**。

### 戦略

- CI中に:
  - これがフレッシュな環境であることを検出
  - すべての既存Kubernetesリソースをインポート
  - その後`terraform apply`を実行

これにより、Terraformステートとkubernetesの現実が**毎回の実行で**整合することを保証しました。

### 結果

- Terraformはリソースの再作成を試みなくなった
- CIパイプラインがべき等になった
- ドリフトが解決された
- Applyが一貫して成功

このアプローチは、ステートレスCI環境のための**ステートブートストラップメカニズム**として意図的に使用されています。

---

## 追加インシデント: セルフホストランナーのディスク容量枯渇

デバッグ中、GitHub Actionsランナーがジョブの取得を停止し、以下でクラッシュしました：

```
No space left on device
/home/ubuntu/actions-runner/_diag/Runner_*.log
```

### 調査

- ルートファイルシステムが**97%使用中**
- 最大の要因:
  - `/var/lib/containerd`
  - `/var/lib/snapd`
  - Kubernetesランタイムアーティファクト

Terraform自体は軽量でしたが、**Kubernetesノードとランナーが同じディスクを共有**していたため、ログ書き込みが失敗しました。

---

## ディスク容量の修正

実行したアクション：

- 未使用のcontainerdイメージとスナップショットをクリーンアップ
- 古いログを削除
- ランナー復旧に必要な最小限の容量を解放
- GitHub Actionsランナーを再登録（登録が自動削除されていた）

容量が解放されると：

- ランナーが正常に再接続
- CI実行が再開

---

## 最終結果

以下の後：

- CIにTerraformインポートロジックを追加
- ランナーのディスク枯渇を修正
- TerraformステートをライブKubernetesリソースと整合

パイプラインは安定状態に達しました：

```
Terraform Init  ✅
Terraform Import ✅
Terraform Apply  ✅
```

Terraformが**信頼できる唯一の情報源**となり、クラスタードリフトを安全に検出・修正できるようになりました。

---

## 学んだ主な教訓

- Terraformは**ステートのみを信頼**し、現実を信頼しない
- CIランナーは**デフォルトでステートレス**
- KubernetesはTerraformの存在を「知らない」
- 既存インフラでTerraformを採用する場合、リソースのインポートは必須
- セルフホストランナーには**ディスク監視が必要**、特にKubernetesノード上では

---

## なぜこれが重要か

このデバッグプロセスは、以下を含む**現実世界のインフラ課題**を反映しています：

- 既存クラスターへのTerraform導入
- CI/CDのべき等性問題
- ステートドリフト復旧
- セルフホストランナーの運用上の制限

このプロジェクトは、Terraform–Kubernetesドリフトを回避する方法だけでなく、**ドリフトから復旧する方法**を意図的に示しています。

---
