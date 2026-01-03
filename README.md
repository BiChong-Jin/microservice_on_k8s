# Kubernetes Microservices on AWS with Terraform & GitHub Actions (Self-Hosted Runner)

## Overview

This project demonstrates an end-to-end deployment of a microservices application on a self-managed Kubernetes cluster (kubeadm) running on AWS EC2, fully managed via Terraform and deployed through GitHub Actions CI/CD using a self-hosted runner.

The project intentionally uses infrastructure-level control (kubeadm, Calico, Security Groups, self-hosted CI runner) to gain a deeper understanding of how Kubernetes, networking, and CI/CD systems work under the hood.

Check the app on : http://52.195.1.85:31184/

## What This Project Demonstrates

- kubeadm cluster setup and debugging
- multi-arch container builds
- Kubernetes networking internals
- DNS and service routing
- AWS Security Group design for Kubernetes
- Terraform state management
- CI/CD with self-hosted GitHub runners
- Real-world debugging methodology

## Architecture

```
User Browser
   |
   | 1) HTTP GET http://<WORKER_PUBLIC_IP>:<NODEPORT>/
   v
Internet
   |
   v
AWS VPC (ap-northeast-1)
┌─────────────────────────────────────────────────────────────────────┐
│ EC2 Worker Node (public IP)                                         │
│                                                                     │
│ 2) Packet hits NodePort (kube-proxy rule on the node)               │
│    <WORKER_PUBLIC_IP>:30997  ->  Service "marketplace" (NodePort)   │
│                                                                     │
│      kube-proxy (iptables/IPVS)                                     │
│           |                                                         │
│           | 3) DNAT / load-balance to one marketplace Pod endpoint  │
│           v                                                         │
│   ┌───────────────────────────────┐                                 │
│   │ marketplace Pod (Flask)       │                                 │
│   │  - listens :5000              │                                 │
│   │  - handles "/" route          │                                 │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 4) gRPC call to "recommendations:50051"         │
│                   |     (DNS + ClusterIP service routing)           │
│                   v                                                 │
│         ┌───────────────────────────────┐                           │
│         │ 5) DNS query to kube-dns       │                          │
│         │    10.96.0.10:53 (CoreDNS)     │                          │
│         └───────────────┬───────────────┘                           │
│                         | returns A record for "recommendations"    │
│                         | (service ClusterIP)                       │
│                         v                                           │
│             recommendations.default.svc.cluster.local               │
│                         -> 10.96.X.Y (ClusterIP)                    │
│                         |                                           │
│                         | 6) TCP connection to 10.96.X.Y:50051      │
│                         v                                           │
│                kube-proxy routes ClusterIP -> Pod endpoint          │
│                         |                                           │
│                         | 7) possibly node-to-node traffic          │
│                         |    (allowed by SG self-referencing rule)  │
│                         v                                           │
│   ┌───────────────────────────────┐                                 │
│   │ recommendations Pod (gRPC)    │                                 │
│   │  - listens :50051             │                                 │
│   │  - returns recommendation list│                                 │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 8) gRPC response back to marketplace Pod        │
│                   v                                                 │
│   ┌───────────────────────────────┐                                 │
│   │ marketplace Pod renders HTML  │                                 │
│   └───────────────┬───────────────┘                                 │
│                   |                                                 │
│                   | 9) HTTP 200 response (HTML)                     │
│                   v                                                 │
└─────────────────────────────────────────────────────────────────────┘
   |
   v
User Browser renders homepage
```

## Services

- marketplace
  - Flask web application

  - Exposed via Kubernetes NodePort

  - Acts as a gRPC client

- recommendations
  - Python gRPC server

  - Provides recommendation data to marketplace

  - The services communicate inside the cluster using Kubernetes Service DNS.

## Infrastructure

- Cloud: AWS EC2

- Kubernetes: kubeadm

- Cluster Topology:
  - 1 master node

  - 2 worker nodes

- CNI: Calico

- DNS: CoreDNS

- IaC: Terraform (Kubernetes provider)

- CI/CD: GitHub Actions + self-hosted runner

- Container Registry: Docker Hub (multi-arch images)

## CI/CD Flow (High Level)

1. Developer commits Terraform or application changes on local machine

2. Code is pushed to GitHub

3. GitHub Actions workflow is triggered

4. GitHub dispatches the job to a self-hosted runner on AWS

5. The runner:
   - checks out the repository

   - runs terraform init / plan / apply

   - applies changes directly to the Kubernetes cluster

6. GitHub receives job status and reports success/failure

## Why a Self-Hosted Runner?

### Why not GitHub-hosted runners?

Using GitHub-hosted runners would require:

- exposing the Kubernetes API publicly or

- complex networking (VPN / bastion / tunneling)

- storing cluster credentials as GitHub secrets

### Why self-hosted worked better here

- Runner lives inside the same AWS environment as the cluster

- Direct, private access to:
  - Kubernetes API

  - kubeconfig

  - internal networking

- Full control over:
  - Terraform version

  - kubectl

  - Docker

  - system configuration

## Key Problems Encountered & Fixes

1. ErrImagePull / ImagePullBackOff

Problem
Pods failed to start with:

```
no match for platform in manifest
```

Cause

- Images were built on Apple Silicon (arm64)

- AWS EC2 nodes are amd64

- Docker Hub image had no amd64 manifest

Fix
Built and pushed multi-architecture images using Docker Buildx:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <image>:v1 \
  --push
```

Why it worked
Kubernetes automatically pulls the correct image based on node architecture.

2. Application returned HTTP 500

Problem
Marketplace service returned 500 Internal Server Error.

Cause
gRPC call failed due to DNS resolution error:

```
DNS resolution failed for recommendations
```

3. Kubernetes DNS Not Working Inside Pods

Diagnosis

- CoreDNS pods were running

- kube-dns service existed

- but nslookup inside a pod timed out

```bash
kubectl run -it --rm dns-test --image=busybox -- sh
nslookup recommendations   # timeout
```

Root Cause
AWS Security Group did not allow node-to-node traffic.

ClusterIP services (including DNS) require:

```
Pod → Node → another Node → Pod
```

This traffic was blocked.

Fix
Added a self-referencing inbound rule to the node Security Group:

- Inbound: All traffic

- Source: the same Security Group

Why it worked
This enabled:

- pod-to-pod networking

- kube-proxy service routing

- DNS (10.96.0.10)

4. Terraform “Already Exists” Errors

Problem
Terraform failed because resources already existed (created manually earlier).

Cause
Terraform state did not know about existing Kubernetes resources.

Resolution (Chosen Approach)
For demo simplicity:

- deleted existing Deployments & Services

- recreated them via Terraform

- reset the GitHub Actions runner to ensure clean state

This ensured:

```
Reality = Terraform State = CI Runner
```

## Terraform as the Source of Truth

After cleanup:

- All Kubernetes resources are created only by Terraform

- No manual kubectl apply for managed resources

- CI/CD pipeline is the single deployment path

This matches real Infrastructure-as-Code best practices.

## Lessons Learned

- NodePort working ≠ ClusterIP working
- Kubernetes DNS issues are often network, not CoreDNS
- AWS Security Groups must explicitly allow intra-cluster traffic
- Terraform trusts state, not reality
- Self-hosted runners are normal and powerful in infra workflows

## Future Improvements

- Move Terraform state to S3 + DynamoDB
- Use Ingress instead of NodePort
- Add terraform plan on PR and manual approval
- Separate CI runner from control plane
- Add monitoring (Prometheus / Grafana)

## Final Note

This project intentionally avoids managed abstractions (EKS, managed CI) to focus on understanding fundamentals. The challenges encountered and solved here are representative of real infrastructure engineering work.
