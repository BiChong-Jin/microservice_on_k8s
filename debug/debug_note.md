# End-to-End Debugging: Image Pull, DNS, and Networking

1. Project Overview

This project deploys a simple microservices architecture on a self-managed Kubernetes cluster (kubeadm) running on AWS EC2:

marketplace

Flask web application

Exposes HTTP endpoint via NodePort

Acts as a gRPC client

recommendations

Python gRPC server

Provides book recommendations

Both services run as Pods inside the cluster and communicate using gRPC over Kubernetes Service DNS.

2. Initial Cluster Setup

Kubernetes installed via kubeadm

1 master node + 2 worker nodes

CNI: Calico

Service CIDR: 10.96.0.0/12

Pod CIDR: 192.168.0.0/16

DNS: CoreDNS

3. Problem #1 — Pods stuck in ErrImagePull
   Symptom

After applying the Kubernetes manifests:

kubectl get pods -w

Pods entered:

ErrImagePull
ImagePullBackOff

Pod Events
Failed to pull image "jinbi/marketplace:v1":
no match for platform in manifest

Root Cause

Docker images were built on Apple Silicon (arm64).

AWS EC2 worker nodes run linux/amd64.

Docker Hub image only contained an arm64 manifest.

Kubernetes strictly pulls images matching the node architecture.

Result: no compatible image → pull failure.

4. Fix #1 — Build and Push Multi-Architecture Images
   Solution

Use Docker Buildx to publish a multi-arch manifest:

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

Why This Worked

Docker Hub now stores two images under the same tag.

Kubernetes automatically selects the correct image based on node architecture.

Pods transition to Running.

5. Problem #2 — Application returns HTTP 500
   Symptom

Accessing the app via NodePort:

http://<worker-public-ip>:30997/

Returned:

500 Internal Server Error

Marketplace Logs
grpc.\_channel.\_InactiveRpcError
StatusCode.UNAVAILABLE
DNS resolution failed for recommendations:50051
Timeout while contacting DNS servers

Interpretation

HTTP networking works (NodePort reachable).

Flask app crashes while calling gRPC.

Failure occurs before any response from recommendations.

Indicates service discovery / DNS failure inside the cluster.

6. Investigation — Is Kubernetes DNS Broken?
   CoreDNS Status
   kubectl -n kube-system get pods

Result:

CoreDNS Pods: Running

kube-dns Service exists

kube-dns has endpoints

So DNS should work.

DNS Test from Inside the Cluster
kubectl run -it --rm dns-test \
 --image=busybox:1.36 \
 --restart=Never -- sh

Inside the pod:

cat /etc/resolv.conf

# nameserver 10.96.0.10

nslookup recommendations

Result:

connection timed out; no servers could be reached

Key Insight

Pods cannot reach 10.96.0.10:53

This is not an application issue

This is cluster networking

7. Root Cause #2 — AWS Security Group Misconfiguration
   Observed Behavior

NodePort access works from the internet

ClusterIP (DNS) does not work inside the cluster

Why This Happens

NodePort traffic:

Internet → Node → Pod

No node-to-node hop

ClusterIP / DNS traffic:

Pod → Node → another Node → Pod

Requires node-to-node communication

The Missing Rule

AWS Security Groups do not automatically allow traffic between instances in the same group.

Your SG allowed:

SSH

NodePort range

API server

VXLAN port

❌ But did NOT allow traffic from the same SG itself.

As a result:

kube-proxy routing to CoreDNS failed

DNS queries silently timed out

gRPC failed due to name resolution failure

8. Fix #2 — Add Self-Referencing Security Group Rule
   The Critical Rule

In the same Security Group attached to all nodes:

Inbound Rule

Type: All traffic

Source: This Security Group itself

(“Self-referencing SG rule”)

Why This Works

Allows:

worker ↔ worker

master ↔ worker

overlay networking (Calico)

kube-proxy service routing

DNS (ClusterIP) traffic

No redeploy required.

9. Verification
   DNS Test (After Fix)
   nslookup recommendations

Result:

Name: recommendations
Address: 10.96.x.x

Application Result

Visiting:

http://52.195.1.85:30997/

Successfully renders:

Mystery books you may like

- Murder on the Orient Express
- The Hound of the Baskervilles
- The Maltese Falcon
