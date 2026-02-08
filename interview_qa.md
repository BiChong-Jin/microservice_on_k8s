# Interview Q&A: Python Microservices on Kubernetes

# 面接 Q&A: Python マイクロサービス on Kubernetes

---

## 1. Project Overview / プロジェクト概要

### Q: Can you give a brief overview of this project?
### Q: このプロジェクトの概要を簡単に説明してください。

**EN:**
This is a two-tier microservices application deployed on a self-managed Kubernetes cluster running on AWS EC2. It consists of a Flask-based marketplace frontend and a gRPC-based recommendations backend. The entire infrastructure is managed with Terraform, and CI/CD is handled by GitHub Actions with a self-hosted runner. I intentionally chose to set up Kubernetes from scratch using kubeadm rather than using a managed service like EKS, in order to deeply understand networking, DNS, and cluster internals.

**JP:**
AWS EC2上にkubeadmで構築した自己管理型Kubernetesクラスタに、2つのマイクロサービスをデプロイしたプロジェクトです。Flaskベースのマーケットプレイス（フロントエンド）と、gRPCベースのレコメンデーション（バックエンド）で構成されています。インフラはTerraformで管理し、CI/CDはセルフホストランナーを使用したGitHub Actionsで自動化しています。EKSのようなマネージドサービスではなく、あえてkubeadmで構築することで、ネットワーキング、DNS、クラスタ内部の仕組みを深く理解することを目指しました。

---

## 2. Architecture / アーキテクチャ

### Q: Why did you choose gRPC over REST for inter-service communication?
### Q: サービス間通信にRESTではなくgRPCを選んだ理由は？

**EN:**
- **Type safety**: Protocol Buffers enforce a strict contract between services via `.proto` files, catching schema mismatches at compile time rather than runtime.
- **Performance**: gRPC uses HTTP/2 and binary serialization, which is more efficient than JSON over HTTP/1.1 for internal service-to-service calls.
- **Language agnostic**: The `.proto` definition can generate client/server stubs in any language, making the system polyglot-ready for future expansion.
- **Streaming support**: gRPC natively supports bidirectional streaming, which would be beneficial if the system needs real-time features later.

**JP:**
- **型安全性**: Protocol Buffersの`.proto`ファイルでサービス間の厳密な契約を定義し、スキーマの不一致をランタイムではなくコンパイル時に検出できます。
- **パフォーマンス**: gRPCはHTTP/2とバイナリシリアライゼーションを使用し、内部通信ではHTTP/1.1上のJSONよりも効率的です。
- **言語非依存**: `.proto`定義から任意の言語のクライアント/サーバースタブを生成でき、将来のポリグロット拡張に対応できます。
- **ストリーミング対応**: gRPCは双方向ストリーミングをネイティブサポートしており、リアルタイム機能が必要になった場合に有利です。

---

### Q: Why did you use kubeadm instead of EKS?
### Q: EKSではなくkubeadmを使った理由は？

**EN:**
The primary goal was learning. Managed Kubernetes abstracts away critical components like etcd, the API server, CNI networking, and CoreDNS. By using kubeadm, I gained hands-on experience with:
- Cluster bootstrapping and node joining
- Calico CNI configuration and pod networking (CIDR: 192.168.0.0/16)
- CoreDNS troubleshooting for service discovery
- Security Group configuration for inter-node communication
- Disk management and etcd operations

In a production environment, I would use EKS for operational reliability, but this experience gives me a much deeper understanding of what's happening beneath the managed layer.

**JP:**
最大の目的は学習です。マネージドKubernetesはetcd、APIサーバー、CNIネットワーキング、CoreDNSなどの重要コンポーネントを抽象化してしまいます。kubeadmを使うことで以下の実践経験を得ました：
- クラスタのブートストラップとノード参加
- Calico CNIの設定とPodネットワーキング（CIDR: 192.168.0.0/16）
- サービスディスカバリのためのCoreDNSトラブルシューティング
- ノード間通信のためのSecurity Group設定
- ディスク管理とetcdの運用

本番環境ではEKSを使いますが、この経験によりマネージドレイヤーの裏側で何が起きているかを深く理解できています。

---

### Q: Explain the request flow from user to response.
### Q: ユーザーからレスポンスまでのリクエストフローを説明してください。

**EN:**
```
User Browser → HTTP Request
  → NodePort Service (port 31184) on any worker node
    → marketplace Pod (Flask on port 5000)
      → gRPC call to recommendations:50051 (ClusterIP, resolved via CoreDNS)
        → recommendations Pod (gRPC server on port 50051)
          → Returns BookRecommendation protobuf response
        → Flask renders Jinja2 template with book data
      → HTTP Response to user
```

The marketplace service uses an environment variable `RECOMMENDATIONS_HOST` to discover the recommendations service, which CoreDNS resolves to the ClusterIP.

**JP:**
```
ユーザーブラウザ → HTTPリクエスト
  → NodePortサービス（ポート31184）任意のワーカーノード
    → marketplace Pod（Flaskポート5000）
      → gRPC呼び出し recommendations:50051（ClusterIP、CoreDNSで名前解決）
        → recommendations Pod（gRPCサーバーポート50051）
          → BookRecommendation protobufレスポンスを返却
        → FlaskがJinja2テンプレートで書籍データをレンダリング
      → HTTPレスポンスをユーザーに返却
```

marketplaceサービスは環境変数`RECOMMENDATIONS_HOST`でレコメンデーションサービスを発見し、CoreDNSがClusterIPに名前解決します。

---

## 3. Infrastructure as Code / IaC

### Q: Why Terraform instead of Helm or raw kubectl?
### Q: Helmや生のkubectlではなくTerraformを選んだ理由は？

**EN:**
- **State management**: Terraform tracks the actual state of resources, enabling drift detection and idempotent operations.
- **Unified IaC**: If I later add AWS resources (S3, RDS, etc.), they can be managed in the same Terraform workflow.
- **Plan before apply**: `terraform plan` shows exactly what will change, reducing deployment risk.
- **Reproducibility**: The entire cluster configuration is declarative and version-controlled.

Helm would be a good addition for templating complex manifests, but for this project's scope, Terraform provides a cleaner single source of truth.

**JP:**
- **状態管理**: Terraformはリソースの実際の状態を追跡し、ドリフト検出と冪等な操作を可能にします。
- **統一IaC**: 将来AWSリソース（S3、RDSなど）を追加する場合、同じTerraformワークフローで管理できます。
- **Plan後にApply**: `terraform plan`で変更内容を事前確認でき、デプロイリスクを低減します。
- **再現性**: クラスタ設定全体が宣言的でバージョン管理されています。

Helmは複雑なマニフェストのテンプレート化に有効ですが、このプロジェクトの規模ではTerraformが単一の信頼できるソースとして適切です。

---

### Q: How do you handle Terraform state in CI/CD?
### Q: CI/CDでTerraformの状態をどう管理していますか？

**EN:**
This was a real challenge. Since the GitHub Actions runner is stateless (no persistent local state file), I implemented a **bootstrap import** strategy: each CI run performs `terraform import` for all existing resources before `plan` or `apply`. This ensures the Terraform state always matches reality. It's idempotent — importing an already-managed resource is a no-op.

I recognize this is not ideal for production. The proper solution would be an S3 backend with DynamoDB locking for remote state management, which I plan to implement as a next step.

**JP:**
これは実際に直面した課題です。GitHub Actionsランナーはステートレス（永続的なローカルstateファイルがない）なため、**ブートストラップインポート**戦略を実装しました。各CI実行で`terraform import`を全既存リソースに対して実行し、`plan`や`apply`の前にTerraformの状態を現実と一致させます。冪等なので、すでに管理されているリソースのインポートは何も起きません。

本番環境では理想的ではないことは認識しています。次のステップとして、S3バックエンド + DynamoDBロックによるリモートstate管理を実装する予定です。

---

## 4. CI/CD Pipeline / CI/CDパイプライン

### Q: Explain your CI/CD pipeline.
### Q: CI/CDパイプラインを説明してください。

**EN:**
The pipeline is defined in `.github/workflows/terraform.yml` and uses a **self-hosted runner** on the same EC2 environment:

1. **On Pull Request** (changes to `infra/terraform/**`):
   - `terraform init` → `terraform validate` → `terraform plan`
   - Plan output is shown for review — no changes are applied.

2. **On Push to main** (changes to `infra/terraform/**`):
   - `terraform init` → `terraform import` (bootstrap) → `terraform validate` → `terraform apply --auto-approve`
   - Changes are applied automatically after merge.

The self-hosted runner was a key design choice: it has direct access to `kubeconfig` at `/home/ubuntu/.kube/config`, so there's no need to expose the Kubernetes API publicly or manage credentials in GitHub Secrets.

**JP:**
パイプラインは`.github/workflows/terraform.yml`で定義され、同じEC2環境上の**セルフホストランナー**を使用しています：

1. **プルリクエスト時**（`infra/terraform/**`の変更）：
   - `terraform init` → `terraform validate` → `terraform plan`
   - Planの出力がレビュー用に表示され、変更は適用されません。

2. **mainへのプッシュ時**（`infra/terraform/**`の変更）：
   - `terraform init` → `terraform import`（ブートストラップ）→ `terraform validate` → `terraform apply --auto-approve`
   - マージ後に変更が自動的に適用されます。

セルフホストランナーは重要な設計判断です。`/home/ubuntu/.kube/config`のkubeconfigに直接アクセスでき、Kubernetes APIを外部公開したりGitHub Secretsで認証情報を管理する必要がありません。

---

### Q: Why a self-hosted runner instead of GitHub-hosted?
### Q: GitHub提供のランナーではなくセルフホストランナーを使う理由は？

**EN:**
- **Security**: The Kubernetes API is not exposed to the internet. The runner accesses it locally.
- **Network access**: Direct connectivity to the cluster's private network without VPN or tunnels.
- **Cost**: No per-minute billing for CI execution time.
- **Latency**: Deploys are faster since the runner is co-located with the cluster.

The trade-off is that I need to maintain the runner infrastructure myself, but since it runs on the same EC2 instances, the operational overhead is minimal.

**JP:**
- **セキュリティ**: Kubernetes APIをインターネットに公開しません。ランナーがローカルでアクセスします。
- **ネットワークアクセス**: VPNやトンネルなしでクラスタのプライベートネットワークに直接接続。
- **コスト**: CI実行時間の従量課金がありません。
- **レイテンシ**: ランナーがクラスタと同じ場所にあるため、デプロイが高速。

トレードオフとしてランナーインフラの維持が必要ですが、同じEC2インスタンス上で動作するため運用負荷は最小限です。

---

## 5. Debugging & Troubleshooting / デバッグ・トラブルシューティング

### Q: What was the most challenging issue you faced?
### Q: 最も困難だった問題は何ですか？

**EN:**
**DNS resolution failure** was the most challenging. The marketplace pod was returning HTTP 500 errors because it couldn't resolve the hostname `recommendations` via gRPC.

**Debugging process:**
1. Checked pod logs → found gRPC connection errors
2. Deployed a busybox pod → ran `nslookup recommendations` → failed
3. Checked CoreDNS pods → they were running fine
4. Realized it was a **network-level** issue, not DNS software
5. Investigated AWS Security Groups → discovered the missing self-referencing rule
6. Added an inbound rule allowing all traffic from the same Security Group
7. DNS resolution and gRPC communication immediately started working

**Key lesson:** In self-managed Kubernetes, DNS problems are often network problems in disguise.

**JP:**
**DNS名前解決の失敗**が最も困難でした。marketplaceのPodがHTTP 500エラーを返しており、gRPC経由で`recommendations`ホスト名を解決できませんでした。

**デバッグプロセス:**
1. Podログを確認 → gRPC接続エラーを発見
2. busybox Podをデプロイ → `nslookup recommendations` → 失敗
3. CoreDNS Podを確認 → 正常動作中
4. DNSソフトウェアではなく**ネットワークレベル**の問題と判断
5. AWS Security Groupsを調査 → 自己参照ルールの欠落を発見
6. 同一Security Groupからの全トラフィックを許可するインバウンドルールを追加
7. DNS名前解決とgRPC通信が即座に復旧

**重要な教訓:** 自己管理Kubernetesでは、DNS問題の正体がネットワーク問題であることが多い。

---

### Q: How did you handle the disk space issue?
### Q: ディスク容量の問題をどう対処しましたか？

**EN:**
The master node's disk reached 100% utilization, causing the Kubernetes API server to shut down — the entire cluster became inaccessible.

**Root cause analysis:**
- containerd images: ~1.8GB
- snapd cache: ~920MB
- etcd data: ~432MB
- systemd journal logs: growing unbounded

**Resolution:**
1. Cleaned up unused container images via `crictl rmi`
2. Cleared systemd journal logs with `journalctl --vacuum-size`
3. Removed unused snap packages
4. Set up cron jobs for automated cleanup to prevent recurrence

**Key takeaway:** Kubernetes control plane components are highly sensitive to disk pressure. Monitoring and alerting on disk usage is essential even for small clusters.

**JP:**
マスターノードのディスク使用率が100%に達し、Kubernetes APIサーバーが停止してクラスタ全体にアクセスできなくなりました。

**根本原因分析:**
- containerdイメージ: 約1.8GB
- snapdキャッシュ: 約920MB
- etcdデータ: 約432MB
- systemdジャーナルログ: 際限なく増加

**解決策:**
1. `crictl rmi`で未使用のコンテナイメージを削除
2. `journalctl --vacuum-size`でsystemdジャーナルログをクリア
3. 未使用のsnapパッケージを削除
4. 再発防止のため自動クリーンアップ用cronジョブを設定

**重要な教訓:** Kubernetesのコントロールプレーンはディスク圧迫に非常に敏感です。小規模クラスタでもディスク使用量の監視とアラートは不可欠です。

---

### Q: How did you solve the multi-architecture image problem?
### Q: マルチアーキテクチャのイメージ問題をどう解決しましたか？

**EN:**
Images built on my local machine (Apple Silicon / arm64) failed to run on AWS EC2 (amd64) with `exec format error` and `ImagePullBackOff`.

**Solution:** Docker Buildx with multi-platform builds:
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t image:tag --push .
```

This creates a manifest list containing both architectures. Kubernetes nodes automatically pull the correct image variant based on their architecture.

**JP:**
ローカルマシン（Apple Silicon / arm64）でビルドしたイメージがAWS EC2（amd64）で`exec format error`と`ImagePullBackOff`で失敗しました。

**解決策:** Docker Buildxによるマルチプラットフォームビルド：
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t image:tag --push .
```

これにより両アーキテクチャを含むマニフェストリストが作成され、Kubernetesノードがアーキテクチャに応じて正しいイメージを自動的に取得します。

---

## 6. Security / セキュリティ

### Q: What security measures have you implemented?
### Q: どのようなセキュリティ対策を実施しましたか？

**EN:**
- **RBAC**: The tfdrift-operator has a dedicated ServiceAccount with a ClusterRole following the principle of least privilege — only the permissions it needs (get, list, watch, patch on Deployments/Services).
- **Self-hosted runner**: Kubernetes API is not exposed to the internet.
- **Slim base images**: `python:3.13-slim` reduces the attack surface compared to full images.
- **Network isolation**: AWS Security Groups control traffic between nodes.

**JP:**
- **RBAC**: tfdrift-operatorは専用のServiceAccountと最小権限の原則に従ったClusterRoleを持ちます（Deployments/Servicesに対するget, list, watch, patchのみ）。
- **セルフホストランナー**: Kubernetes APIをインターネットに公開しません。
- **スリムベースイメージ**: `python:3.13-slim`でフルイメージと比較して攻撃対象面を削減。
- **ネットワーク分離**: AWS Security Groupsでノード間のトラフィックを制御。

---

### Q: What security improvements would you make for production?
### Q: 本番環境に向けてどのようなセキュリティ改善を行いますか？

**EN:**
1. **mTLS for gRPC**: Currently using `insecure_channel`. Would implement mutual TLS for encrypted, authenticated service-to-service communication.
2. **Network Policies**: Restrict which pods can communicate with each other (e.g., only marketplace → recommendations).
3. **Pod Security Standards**: Enforce non-root containers, read-only root filesystems, and drop all capabilities.
4. **Secrets management**: Use AWS Secrets Manager or HashiCorp Vault instead of plain environment variables.
5. **Terraform remote state encryption**: S3 backend with server-side encryption and DynamoDB locking.
6. **Image scanning**: Add Trivy or Snyk to CI pipeline for vulnerability scanning.
7. **Audit logging**: Enable Kubernetes audit logs to track API server access.

**JP:**
1. **gRPCのmTLS化**: 現在`insecure_channel`を使用。相互TLSで暗号化・認証されたサービス間通信を実装。
2. **Network Policy**: Pod間通信を制限（例：marketplace → recommendationsのみ許可）。
3. **Pod Security Standards**: 非rootコンテナ、読み取り専用ルートファイルシステム、全capabilities削除を強制。
4. **シークレット管理**: 環境変数の代わりにAWS Secrets ManagerやHashiCorp Vaultを使用。
5. **Terraform remote stateの暗号化**: サーバーサイド暗号化付きS3バックエンド + DynamoDBロック。
6. **イメージスキャン**: CIパイプラインにTrivyやSnykを追加して脆弱性スキャン。
7. **監査ログ**: Kubernetes監査ログを有効化してAPIサーバーへのアクセスを追跡。

---

## 7. Scalability & Future Improvements / スケーラビリティと今後の改善

### Q: How would you scale this system?
### Q: このシステムをどのようにスケールしますか？

**EN:**
- **Horizontal Pod Autoscaler (HPA)**: Auto-scale pods based on CPU/memory metrics.
- **Cluster Autoscaler**: Add/remove EC2 worker nodes based on pending pod demand.
- **Ingress Controller**: Replace NodePort with an Nginx or AWS ALB Ingress for load balancing and TLS termination.
- **Database layer**: Add a managed database (RDS) for persistent data with read replicas for scaling reads.
- **Caching**: Introduce Redis for frequently accessed recommendation data.
- **Service Mesh**: Istio or Linkerd for advanced traffic management, circuit breaking, and observability.

**JP:**
- **Horizontal Pod Autoscaler (HPA)**: CPU/メモリメトリクスに基づくPodの自動スケーリング。
- **Cluster Autoscaler**: 保留中のPod需要に応じてEC2ワーカーノードを追加/削除。
- **Ingressコントローラ**: NodePortをNginxまたはAWS ALB Ingressに置き換え、負荷分散とTLS終端を実現。
- **データベース層**: 永続データ用にマネージドデータベース（RDS）を追加し、読み取りスケーリング用のリードレプリカ。
- **キャッシュ**: 頻繁にアクセスされるレコメンデーションデータにRedisを導入。
- **サービスメッシュ**: IstioやLinkerdで高度なトラフィック管理、サーキットブレーカー、オブザーバビリティを実現。

---

### Q: What observability would you add?
### Q: どのようなオブザーバビリティを追加しますか？

**EN:**
Currently the project lacks structured observability. I would add the three pillars:

1. **Metrics**: Prometheus + Grafana for cluster and application metrics (request latency, error rates, pod resource usage).
2. **Logging**: Fluent Bit → CloudWatch Logs or Loki for centralized, searchable log aggregation.
3. **Tracing**: OpenTelemetry with Jaeger to trace requests across marketplace → recommendations gRPC calls.
4. **Alerting**: PagerDuty or Slack integration for critical alerts (disk usage > 80%, pod restarts, 5xx spike).

**JP:**
現在、構造化されたオブザーバビリティがありません。3つの柱を追加します：

1. **メトリクス**: Prometheus + Grafanaでクラスタとアプリケーションのメトリクス（リクエストレイテンシ、エラー率、Podリソース使用量）。
2. **ログ**: Fluent Bit → CloudWatch LogsまたはLokiで集中的な検索可能なログ集約。
3. **トレーシング**: OpenTelemetry + Jaegerでmarketplace → recommendations間のgRPC呼び出しをトレース。
4. **アラート**: PagerDutyやSlack連携で重要アラート（ディスク使用率80%超、Pod再起動、5xxスパイク）。

---

## 8. Design Trade-offs / 設計上のトレードオフ

### Q: What trade-offs did you consciously make?
### Q: 意識的に行ったトレードオフは何ですか？

**EN:**
| Decision | Trade-off | Reason |
|---|---|---|
| kubeadm over EKS | More operational burden, less reliability | Deeper learning of K8s internals |
| Terraform over Helm | Less templating flexibility | Single source of truth for all resources |
| NodePort over Ingress | No TLS termination, no load balancing | Simpler setup for self-managed cluster |
| Self-hosted runner | Runner maintenance required | No need to expose K8s API externally |
| insecure gRPC | No encryption for internal traffic | Acceptable for learning; flagged for production fix |
| Bootstrap import | Not scalable, runs on every CI | Solves stateless runner problem without remote state |

**JP:**
| 判断 | トレードオフ | 理由 |
|---|---|---|
| EKSではなくkubeadm | 運用負荷増、信頼性低下 | K8s内部の深い理解 |
| Helmではなく Terraform | テンプレートの柔軟性低下 | 全リソースの単一信頼ソース |
| Ingressではなく NodePort | TLS終端なし、負荷分散なし | 自己管理クラスタでのシンプルな構成 |
| セルフホストランナー | ランナーのメンテナンスが必要 | K8s APIの外部公開不要 |
| 非暗号化gRPC | 内部トラフィックの暗号化なし | 学習目的では許容。本番では修正予定 |
| ブートストラップインポート | スケーラブルでなく毎CI実行 | リモートstateなしでステートレスランナー問題を解決 |

---

## 9. Behavioral / Deep Questions / 行動・深掘り質問

### Q: What would you do differently if starting from scratch?
### Q: 最初からやり直すなら何を変えますか？

**EN:**
1. **Set up remote Terraform state first** (S3 + DynamoDB) before any other infrastructure.
2. **Add monitoring from day one** — the disk space crisis could have been prevented with basic alerts.
3. **Write tests before deployment** — currently testing is manual; I'd add pytest unit tests and gRPC integration tests into the CI pipeline.
4. **Start with Ingress** rather than migrating from NodePort later.
5. **Document architecture decisions** using ADRs (Architecture Decision Records) from the beginning.

**JP:**
1. **Terraform remote stateを最初に構築**（S3 + DynamoDB）してから他のインフラに着手。
2. **初日から監視を導入** — ディスク容量危機は基本的なアラートで防げた。
3. **デプロイ前にテストを記述** — 現在のテストは手動。pytestのユニットテストとgRPC統合テストをCIパイプラインに追加。
4. **最初からIngress**を使い、後からNodePortから移行する手間を省く。
5. **ADR（Architecture Decision Records）**で設計判断を最初から文書化。

---

### Q: How does this project demonstrate your engineering skills?
### Q: このプロジェクトはあなたのエンジニアリングスキルをどう示していますか？

**EN:**
- **Problem solving**: Debugged complex issues spanning multiple layers (application → Kubernetes → AWS networking) without falling back to managed services.
- **Infrastructure mindset**: Built everything as code (Terraform, CI/CD), not manual operations.
- **Operational awareness**: Documented every issue with root cause analysis and preventive measures — not just fixes.
- **Security consciousness**: Implemented RBAC, used slim images, kept the API private. Identified and documented remaining gaps.
- **Growth mindset**: Chose the harder path (kubeadm) specifically to build deeper understanding, and clearly articulate what I'd improve.

**JP:**
- **問題解決力**: 複数レイヤー（アプリケーション → Kubernetes → AWSネットワーキング）にまたがる複雑な問題を、マネージドサービスに頼らずデバッグ。
- **インフラのマインドセット**: すべてをコード（Terraform、CI/CD）で構築し、手動操作を排除。
- **運用への意識**: すべての問題を根本原因分析と予防策とともに文書化 — 単なる修正に留まらない。
- **セキュリティ意識**: RBACの実装、スリムイメージの使用、APIの非公開化。残存するギャップも特定・文書化。
- **成長志向**: より深い理解を構築するためにあえて困難な道（kubeadm）を選択し、改善点を明確に言語化。

---

## 10. Quick-Fire Technical Questions / 技術クイックファイア

### Q: What is the difference between ClusterIP and NodePort?
### Q: ClusterIPとNodePortの違いは？

**EN:**
- **ClusterIP**: Only accessible within the cluster. Used for internal service-to-service communication (recommendations service uses this).
- **NodePort**: Exposes the service on a static port on every node's IP. Accessible from outside the cluster (marketplace uses this).

**JP:**
- **ClusterIP**: クラスタ内部からのみアクセス可能。内部のサービス間通信に使用（recommendationsサービス）。
- **NodePort**: 各ノードのIPの静的ポートでサービスを公開。クラスタ外部からアクセス可能（marketplaceサービス）。

---

### Q: What happens if the recommendations pod goes down?
### Q: recommendations Podがダウンしたらどうなりますか？

**EN:**
The marketplace service would return HTTP 500 errors because the gRPC call would fail. Currently there's no circuit breaker, retry logic, or graceful fallback. For production, I would:
1. Add retry with exponential backoff in the gRPC client
2. Implement a circuit breaker pattern (e.g., using `tenacity` library)
3. Return a degraded response (e.g., "Recommendations unavailable") instead of 500
4. Ensure the Deployment has `replicas > 1` for high availability

**JP:**
gRPC呼び出しが失敗するため、marketplaceサービスはHTTP 500エラーを返します。現在、サーキットブレーカー、リトライロジック、グレースフルフォールバックはありません。本番環境では：
1. gRPCクライアントに指数バックオフ付きリトライを追加
2. サーキットブレーカーパターンを実装（例：`tenacity`ライブラリ）
3. 500の代わりにデグレードレスポンスを返却（例：「レコメンデーションは利用不可」）
4. 高可用性のためDeploymentの`replicas > 1`を確保

---

### Q: Explain Protocol Buffers and how they're used here.
### Q: Protocol Buffersとこのプロジェクトでの使い方を説明してください。

**EN:**
Protocol Buffers (protobuf) is Google's language-neutral serialization format. In this project:

1. `recommendations.proto` defines the service contract — request/response message types and RPC methods.
2. `grpc_tools.protoc` compiles the `.proto` file into Python code:
   - `recommendations_pb2.py` — message classes (serialization/deserialization)
   - `recommendations_pb2_grpc.py` — client stub and server base class
3. The recommendations server implements the generated base class.
4. The marketplace client uses the generated stub to make type-safe RPC calls.

This ensures both services agree on the exact data format at compile time, not runtime.

**JP:**
Protocol Buffers（protobuf）はGoogleの言語中立なシリアライゼーション形式です。このプロジェクトでは：

1. `recommendations.proto`でサービス契約を定義 — リクエスト/レスポンスのメッセージ型とRPCメソッド。
2. `grpc_tools.protoc`が`.proto`ファイルをPythonコードにコンパイル：
   - `recommendations_pb2.py` — メッセージクラス（シリアライズ/デシリアライズ）
   - `recommendations_pb2_grpc.py` — クライアントスタブとサーバー基底クラス
3. recommendationsサーバーが生成された基底クラスを実装。
4. marketplaceクライアントが生成されたスタブで型安全なRPC呼び出しを実行。

これにより両サービスがランタイムではなくコンパイル時に正確なデータ形式に合意します。

---

### Q: What is the tfdrift-operator and why did you build it?
### Q: tfdrift-operatorとは何で、なぜ作りましたか？

**EN:**
The tfdrift-operator is a custom Kubernetes controller that monitors for configuration drift — when the actual state of cluster resources diverges from what Terraform defines. It runs in its own namespace (`tfdrift-operator-system`) with dedicated RBAC permissions.

The motivation came from real experience: when debugging issues, it's tempting to make manual `kubectl` changes that aren't reflected in Terraform. The operator watches for such drift and can alert or reconcile.

**JP:**
tfdrift-operatorは、Kubernetesリソースの実際の状態がTerraformの定義から乖離する設定ドリフトを監視するカスタムKubernetesコントローラーです。専用のnamespace（`tfdrift-operator-system`）とRBAC権限で動作します。

動機は実体験から来ています。問題のデバッグ中に手動で`kubectl`変更を行いたくなりますが、それはTerraformに反映されません。このオペレーターがそのようなドリフトを検出し、アラートや修復を行います。

---

## Tips for the Interview / 面接のコツ

**EN:**
- Always explain **WHY** you made a decision, not just what you did.
- Be honest about limitations and what you'd improve — interviewers value self-awareness.
- Connect debugging stories to lessons learned — show growth.
- Mention the production-readiness gap intentionally to demonstrate you know the difference between learning projects and production systems.

**JP:**
- 何をしたかだけでなく、**なぜ**その判断をしたかを常に説明する。
- 制約や改善点について正直に — 面接官は自己認識を評価します。
- デバッグのエピソードを学びに結びつける — 成長を示す。
- 本番対応とのギャップを意図的に言及し、学習プロジェクトと本番システムの違いを理解していることを示す。
