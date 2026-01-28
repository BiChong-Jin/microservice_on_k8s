# AWS上のKubernetesマイクロサービス - Terraform & GitHub Actions（セルフホストランナー）

## 概要

このプロジェクトは、AWS EC2上で動作するセルフマネージドKubernetesクラスター（kubeadm）にマイクロサービスアプリケーションをエンドツーエンドでデプロイするデモンストレーションです。インフラはTerraformで完全に管理され、セルフホストランナーを使用したGitHub Actions CI/CDを通じてデプロイされます。

このプロジェクトでは、Kubernetes、ネットワーキング、CI/CDシステムの内部動作をより深く理解するために、意図的にインフラレベルの制御（kubeadm、Calico、セキュリティグループ、セルフホストCIランナー）を使用しています。

アプリはこちらで確認できます: http://52.195.1.85:31184/

## このプロジェクトが示すもの

- kubeadmクラスターのセットアップとデバッグ
- マルチアーキテクチャコンテナビルド
- Kubernetesネットワーキングの内部構造
- DNSとサービスルーティング
- Kubernetes向けAWSセキュリティグループ設計
- Terraformステート管理
- セルフホストGitHubランナーによるCI/CD
- 実践的なデバッグ手法

## アーキテクチャ

```
ユーザーブラウザ
   |
   | 1) HTTP GET http://<WORKER_PUBLIC_IP>:<NODEPORT>/
   v
インターネット
   |
   v
AWS VPC (ap-northeast-1)
┌─────────────────────────────────────────────────────────────────────┐
│ EC2 ワーカーノード (パブリックIP)                                    │
│                                                                     │
│ 2) パケットがNodePortに到達 (ノード上のkube-proxyルール)              │
│    <WORKER_PUBLIC_IP>:30997  ->  Service "marketplace" (NodePort)   │
│                                                                     │
│      kube-proxy (iptables/IPVS)                                     │
│           |                                                         │
│           | 3) DNAT / marketplacePodエンドポイントへのロードバランス   │
│           v                                                         │
│   ┌───────────────────────────────┐                                 │
│   │ marketplace Pod (Flask)       │                                 │
│   │  - ポート5000でリッスン         │                                 │
│   │  - "/" ルートを処理            │                                 │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 4) "recommendations:50051" へのgRPC呼び出し      │
│                   |     (DNS + ClusterIPサービスルーティング)         │
│                   v                                                 │
│         ┌───────────────────────────────┐                           │
│         │ 5) kube-dnsへのDNSクエリ        │                          │
│         │    10.96.0.10:53 (CoreDNS)     │                          │
│         └───────────────┬───────────────┘                           │
│                         | "recommendations" のAレコードを返す         │
│                         | (サービスClusterIP)                        │
│                         v                                           │
│             recommendations.default.svc.cluster.local               │
│                         -> 10.96.X.Y (ClusterIP)                    │
│                         |                                           │
│                         | 6) 10.96.X.Y:50051 へのTCP接続             │
│                         v                                           │
│                kube-proxyがClusterIPをPodエンドポイントにルーティング  │
│                         |                                           │
│                         | 7) ノード間トラフィックの可能性              │
│                         |    (SG自己参照ルールで許可)                 │
│                         v                                           │
│   ┌───────────────────────────────┐                                 │
│   │ recommendations Pod (gRPC)    │                                 │
│   │  - ポート50051でリッスン        │                                 │
│   │  - レコメンデーションリストを返す │                                 │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 8) marketplace PodへのgRPCレスポンス             │
│                   v                                                 │
│   ┌───────────────────────────────┐                                 │
│   │ marketplace PodがHTMLをレンダリング │                             │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 9) HTTP 200 レスポンス (HTML)                    │
│                   v                                                 │
└─────────────────────────────────────────────────────────────────────┘
   |
   v
ユーザーブラウザがホームページをレンダリング
```

## サービス

- marketplace
  - Flask Webアプリケーション

  - Kubernetes NodePortで公開

  - gRPCクライアントとして動作

- recommendations
  - Python gRPCサーバー

  - marketplaceにレコメンデーションデータを提供

  - サービス間はKubernetes Service DNSを使用してクラスター内で通信

## インフラストラクチャ

- クラウド: AWS EC2

- Kubernetes: kubeadm

- クラスター構成:
  - マスターノード 1台

  - ワーカーノード 2台

- CNI: Calico

- DNS: CoreDNS

- IaC: Terraform (Kubernetesプロバイダー)

- CI/CD: GitHub Actions + セルフホストランナー

- コンテナレジストリ: Docker Hub (マルチアーキテクチャイメージ)

## CI/CDフロー（概要）

1. 開発者がローカルマシンでTerraformまたはアプリケーションの変更をコミット

2. コードがGitHubにプッシュされる

3. GitHub Actionsワークフローがトリガーされる

4. GitHubがジョブをAWS上のセルフホストランナーにディスパッチ

5. ランナーが実行する処理:
   - リポジトリをチェックアウト

   - terraform init / plan / apply を実行

   - Kubernetesクラスターに変更を直接適用

6. GitHubがジョブステータスを受信し、成功/失敗を報告

## なぜセルフホストランナーなのか？

### なぜGitHubホストランナーではないのか？

GitHubホストランナーを使用する場合、以下が必要になります:

- Kubernetes APIをパブリックに公開する、または

- 複雑なネットワーク構成（VPN / 踏み台 / トンネリング）

- クラスター認証情報をGitHub Secretsとして保存

### ここでセルフホストがより適している理由

- ランナーがクラスターと同じAWS環境内に存在

- 以下への直接的なプライベートアクセス:
  - Kubernetes API

  - kubeconfig

  - 内部ネットワーク

- 以下を完全に制御:
  - Terraformバージョン

  - kubectl

  - Docker

  - システム設定

## 発生した主な問題と解決策

1. ErrImagePull / ImagePullBackOff

問題
Podが以下のエラーで起動に失敗:

```
no match for platform in manifest
```

原因

- イメージがApple Silicon (arm64)でビルドされていた

- AWS EC2ノードはamd64

- Docker Hubイメージにamd64マニフェストがなかった

解決策
Docker Buildxを使用してマルチアーキテクチャイメージをビルド・プッシュ:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <image>:v1 \
  --push
```

なぜこれで解決したか
Kubernetesはノードアーキテクチャに基づいて自動的に正しいイメージをプルします。

2. アプリケーションがHTTP 500を返す

問題
MarketplaceサービスがHTTP 500 Internal Server Errorを返した。

原因
DNS解決エラーによりgRPC呼び出しが失敗:

```
DNS resolution failed for recommendations
```

3. Pod内でKubernetes DNSが機能しない

診断

- CoreDNS Podは実行中

- kube-dnsサービスは存在

- しかしPod内でのnslookupがタイムアウト

```bash
kubectl run -it --rm dns-test --image=busybox -- sh
nslookup recommendations   # タイムアウト
```

根本原因
AWSセキュリティグループがノード間トラフィックを許可していなかった。

ClusterIPサービス（DNSを含む）には以下が必要:

```
Pod → ノード → 別のノード → Pod
```

このトラフィックがブロックされていた。

解決策
ノードセキュリティグループに自己参照インバウンドルールを追加:

- インバウンド: すべてのトラフィック

- ソース: 同じセキュリティグループ

なぜこれで解決したか
これにより以下が有効になった:

- Pod間ネットワーキング

- kube-proxyサービスルーティング

- DNS (10.96.0.10)

4. Terraform「Already Exists」エラー

問題
リソースが既に存在する（以前手動で作成）ためTerraformが失敗。

原因
Terraformステートが既存のKubernetesリソースを認識していなかった。

解決策（採用したアプローチ）
デモの簡素化のため:

- 既存のDeploymentとServiceを削除

- Terraformで再作成

- GitHub Actionsランナーをリセットしてクリーンな状態を確保

これにより以下を保証:

```
現実 = Terraformステート = CIランナー
```

## 信頼できる唯一の情報源としてのTerraform

クリーンアップ後:

- すべてのKubernetesリソースはTerraformのみで作成

- 管理対象リソースへの手動kubectl applyなし

- CI/CDパイプラインが唯一のデプロイパス

これは実際のInfrastructure-as-Codeのベストプラクティスに合致しています。

## 学んだ教訓

- NodePortが動作 ≠ ClusterIPが動作
- Kubernetes DNSの問題は多くの場合CoreDNSではなくネットワークの問題
- AWSセキュリティグループはクラスター内トラフィックを明示的に許可する必要がある
- Terraformは現実ではなくステートを信頼する
- セルフホストランナーはインフラワークフローでは一般的かつ強力

## 今後の改善点

- TerraformステートをS3 + DynamoDBに移行
- NodePortの代わりにIngressを使用
- PR時のterraform planと手動承認を追加
- CIランナーをコントロールプレーンから分離
- モニタリングを追加（Prometheus / Grafana）

## 最後に

このプロジェクトは、基礎の理解に焦点を当てるため、マネージドな抽象化（EKS、マネージドCI）を意図的に避けています。ここで遭遇し解決した課題は、実際のインフラエンジニアリング業務を代表するものです。
