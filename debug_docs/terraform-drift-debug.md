# Terraform × Kubernetes Drift Debugging Story

## Background

This project manages a Kubernetes cluster using **Terraform**, executed via a **self-hosted GitHub Actions runner** running on an AWS EC2 instance.

The cluster itself already contained resources created earlier (Deployments, Services, RBAC objects). Terraform was introduced later to fully manage these resources and enforce desired state via CI/CD.

---

## Initial Problem: Terraform Apply Keeps Failing

After pushing Terraform code to GitHub, the CI pipeline failed repeatedly with errors like:

```
deployments.apps "marketplace" already exists
services "recommendations" already exists
namespaces "tfdrift-operator-system" already exists
```

Terraform consistently attempted to **create resources that already existed** in the cluster.

---

## Root Cause #1: Terraform State Was Empty in CI

Although Terraform commands (`import`, `plan`, `apply`) were run manually on the self-hosted runner at some point, **Terraform state was not persisted** between CI runs.

Important facts:

- Terraform was **never run locally** on the developer machine
- The self-hosted runner is **ephemeral**
- Each GitHub Actions run starts with:
  - a fresh checkout
  - an **empty Terraform state**

- Kubernetes already contained the resources

So every CI run behaved like:

> “State is empty → everything must be created”

Which immediately conflicted with reality.

---

## Failed Attempt: Manual `terraform import`

Manually running `terraform import` on the runner **did not fix the CI**, because:

- GitHub Actions runs in a **clean environment**
- Imported state was **not available** to subsequent CI runs
- CI never executed `terraform import`

This resulted in Terraform repeatedly attempting to recreate existing resources.

---

## Root Cause #2: CI Pipeline Lacked State Reconciliation

The original workflow:

```yaml
terraform init
terraform validate
terraform plan
terraform apply
```

Had **no step to reconcile live Kubernetes state into Terraform state**.

Terraform was technically correct — it simply had no idea those resources already existed.

---

## Solution: Bootstrap Terraform State Inside CI

To fix this, a **Terraform import step was added directly into the CI workflow**.

### Strategy

- During CI:
  - Detect that this is a fresh environment
  - Import all pre-existing Kubernetes resources
  - Then run `terraform apply`

This ensured Terraform state and Kubernetes reality were aligned **every run**.

### Result

- Terraform stopped trying to recreate resources
- CI pipeline became idempotent
- Drift was resolved
- Apply succeeded consistently

This approach is intentionally used as a **state bootstrapping mechanism** for a stateless CI environment.

---

## Additional Incident: Self-Hosted Runner Disk Space Exhaustion

During debugging, the GitHub Actions runner stopped picking up jobs and crashed with:

```
No space left on device
/home/ubuntu/actions-runner/_diag/Runner_*.log
```

### Investigation

- Root filesystem was at **97% usage**
- Largest contributors:
  - `/var/lib/containerd`
  - `/var/lib/snapd`
  - Kubernetes runtime artifacts

Although Terraform itself was lightweight, the **Kubernetes node and runner shared the same disk**, causing log writes to fail.

---

## Disk Space Fix

Actions taken:

- Cleaned unused containerd images and snapshots
- Removed stale logs
- Freed minimal space to allow runner recovery
- Re-registered the GitHub Actions runner (registration was auto-deleted)

Once space was freed:

- Runner successfully reconnected
- CI resumed execution

---

## Final Outcome

After:

- Adding Terraform import logic to CI
- Fixing runner disk exhaustion
- Aligning Terraform state with live Kubernetes resources

The pipeline reached a stable state:

```
Terraform Init  ✅
Terraform Import ✅
Terraform Apply  ✅
```

Terraform is now the **single source of truth**, and cluster drift can be safely detected and corrected.

---

## Key Lessons Learned

- Terraform **only trusts state**, not reality
- CI runners are **stateless by default**
- Kubernetes does not “know” Terraform exists
- Importing resources is mandatory when adopting Terraform on existing infrastructure
- Self-hosted runners require **disk monitoring**, especially on Kubernetes nodes

---

## Why This Matters

This debugging process reflects **real-world infrastructure challenges**, including:

- Terraform adoption on existing clusters
- CI/CD idempotency issues
- State drift recovery
- Operational limits of self-hosted runners

This project intentionally demonstrates how to **recover from Terraform–Kubernetes drift**, not just how to avoid it.

---
