# Kubernetes Microservices on AWS with Terraform & GitHub Actions (Self-Hosted Runner)

## Overview

This project demonstrates an end-to-end deployment of a microservices application on a self-managed Kubernetes cluster (kubeadm) running on AWS EC2, fully managed via Terraform and deployed through GitHub Actions CI/CD using a self-hosted runner.

The project intentionally uses infrastructure-level control (kubeadm, Calico, Security Groups, self-hosted CI runner) to gain a deeper understanding of how Kubernetes, networking, and CI/CD systems work under the hood.

## Architecture

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
