# エンドツーエンドデバッグ: イメージプル、DNS、ネットワーキング

1. プロジェクト概要

このプロジェクトは、AWS EC2上で動作するセルフマネージドKubernetesクラスター（kubeadm）にシンプルなマイクロサービスアーキテクチャをデプロイします：

marketplace

Flask Webアプリケーション

NodePort経由でHTTPエンドポイントを公開

gRPCクライアントとして動作

recommendations

Python gRPCサーバー

書籍のレコメンデーションを提供

両サービスはクラスター内のPodとして実行され、Kubernetes Service DNS上のgRPCを使用して通信します。

2. 初期クラスターセットアップ

kubeadmでKubernetesをインストール

マスターノード1台 + ワーカーノード2台

CNI: Calico

Service CIDR: 10.96.0.0/12

Pod CIDR: 192.168.0.0/16

DNS: CoreDNS

3. 問題 #1 — PodがErrImagePullで停止
   症状

Kubernetesマニフェストを適用後：

kubectl get pods -w

Podが以下の状態になった：

ErrImagePull
ImagePullBackOff

Podイベント
Failed to pull image "jinbi/marketplace:v1":
no match for platform in manifest

根本原因

DockerイメージがApple Silicon (arm64)でビルドされていた。

AWS EC2ワーカーノードはlinux/amd64で動作。

Docker Hubイメージにはarm64マニフェストのみが含まれていた。

Kubernetesはノードアーキテクチャに一致するイメージのみを厳密にプルする。

結果：互換性のあるイメージがない → プル失敗。

4. 修正 #1 — マルチアーキテクチャイメージのビルドとプッシュ
   解決策

Docker Buildxを使用してマルチアーキテクチャマニフェストを公開：

docker buildx create --use
docker buildx inspect --bootstrap

docker buildx build \
 --platform linux/amd64,linux/arm64 \
 -t jinbi/marketplace:v1 \
 --push \
 ./marketplace

docker buildx build \
 --platform linux/amd64,linux/arm64 \
 -t jinbi/recommendations:v1 \
 --push \
 ./recommendations

なぜこれで解決したか

Docker Hubは同じタグの下に2つのイメージを保存するようになった。

Kubernetesはノードアーキテクチャに基づいて自動的に正しいイメージを選択。

PodがRunning状態に遷移。

5. 問題 #2 — アプリケーションがHTTP 500を返す
   症状

NodePort経由でアプリにアクセス：

http://<worker-public-ip>:30997/

返されたエラー：

500 Internal Server Error

Marketplaceログ
grpc.\_channel.\_InactiveRpcError
StatusCode.UNAVAILABLE
DNS resolution failed for recommendations:50051
Timeout while contacting DNS servers

解釈

HTTPネットワーキングは動作（NodePortに到達可能）。

FlaskアプリがgRPC呼び出し中にクラッシュ。

recommendationsからの応答前に失敗が発生。

クラスター内のサービスディスカバリ / DNS障害を示唆。

6. 調査 — Kubernetes DNSは壊れているか？
   CoreDNSステータス
   kubectl -n kube-system get pods

結果：

CoreDNS Pod: Running

kube-dnsサービスが存在

kube-dnsにエンドポイントあり

つまりDNSは動作するはず。

クラスター内からのDNSテスト
kubectl run -it --rm dns-test \
 --image=busybox:1.36 \
 --restart=Never -- sh

Pod内で：

cat /etc/resolv.conf

# nameserver 10.96.0.10

nslookup recommendations

結果：

connection timed out; no servers could be reached

重要な発見

Podが10.96.0.10:53に到達できない

これはアプリケーションの問題ではない

これはクラスターネットワーキングの問題

7. 根本原因 #2 — AWSセキュリティグループの設定ミス
   観察された動作

NodePortアクセスはインターネットから動作

ClusterIP (DNS)はクラスター内で動作しない

なぜこうなるのか

NodePortトラフィック：

インターネット → ノード → Pod

ノード間ホップなし

ClusterIP / DNSトラフィック：

Pod → ノード → 別のノード → Pod

ノード間通信が必要

欠けていたルール

AWSセキュリティグループは、同じグループ内のインスタンス間のトラフィックを自動的に許可しない。

あなたのSGが許可していたもの：

SSH

NodePortレンジ

APIサーバー

VXLANポート

❌ しかし、同じSG自体からのトラフィックは許可されていなかった。

結果として：

CoreDNSへのkube-proxyルーティングが失敗

DNSクエリがサイレントにタイムアウト

名前解決失敗によりgRPCが失敗

8. 修正 #2 — 自己参照セキュリティグループルールの追加
   重要なルール

すべてのノードにアタッチされている同じセキュリティグループ内で：

インバウンドルール

タイプ: すべてのトラフィック

ソース: このセキュリティグループ自体

（「自己参照SGルール」）

なぜこれで解決するか

以下を許可：

ワーカー ↔ ワーカー

マスター ↔ ワーカー

オーバーレイネットワーキング（Calico）

kube-proxyサービスルーティング

DNS（ClusterIP）トラフィック

再デプロイ不要。

9. 検証
   DNSテスト（修正後）
   nslookup recommendations

結果：

Name: recommendations
Address: 10.96.x.x

アプリケーション結果

アクセス：

http://52.195.1.85:30997/

正常にレンダリング：

Mystery books you may like

- Murder on the Orient Express
- The Hound of the Baskervilles
- The Maltese Falcon
