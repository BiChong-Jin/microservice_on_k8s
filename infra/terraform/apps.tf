# --- recommendations --------
resource "kubernetes_deployment" "recommendations" {
  metadata {
    name   = "recommendations"
    labels = { app = "recommendations" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "recommendations" } }

    template {
      metadata { labels = { app = "recommendations" } }
      spec {
        # pin to worker node2 by label, if you already labeled it:
        # node_selector = { role = "recommendations" }

        container {
          name  = "recommendations"
          image = "jinbi/recommendations:v1"
          port { container_port = 50051 }
        }
      }
    }
  }
}

resource "kubernetes_service" "recommendations" {
  metadata { name = "recommendations" }
  spec {
    selector = { app = "recommendations" }
    port { 
      port        = 50051
      target_port = 50051
    }
    type = "ClusterIP"
  }
}

# --- marketplace ---
resource "kubernetes_deployment" "marketplace" {
  metadata {
    name   = "marketplace"
    labels = { app = "marketplace" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "marketplace" } }

    template {
      metadata { labels = { app = "marketplace" } }
      spec {
        # pin to worker node1 by label:
        # node_selector = { role = "marketplace" }

        container {
          name  = "marketplace"
          image = "jinbi/marketplace:v1"

          env { 
            name = "RECOMMENDATIONS_HOST" 
            value = "recommendations" 
          }

          port { container_port = 5000 }
        }
      }
    }
  }
}

resource "kubernetes_service" "marketplace" {
  metadata { name = "marketplace" }
  spec {
    selector = { app = "marketplace" }
    port { 
      port = 80 
      target_port = 5000 
    }
    type = "NodePort" # safest for kubeadm demo; switch to LB/Ingress later
  }
}

# --- tfdrift-operator ---
resource "kubernetes_namespace" "tfdrift-operator" {
  metadata {name = "tfdrift-operator-system"}
}

resource "kubernetes_service_account" "tfdrift-operator" {
  metadata {
    name = "tfdrift-operator"
    namespace = kubernetes_namespace.tfdrift-operator.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "tfdrift-operator" {
  metadata {name = "tfdrift-operator"}

  rule {
    api_groups = ["apps"]
    resources = ["deployment"]
    verbs = ["get", "list", "watch", "patch", "update"]
  }

  rule {
    api_groups = [""]
    resources = ["services"]
    verbs = ["get", "list", "watch", "patch", "update"]
  }

  rule {
    api_groups = [""]
    resources = ["events"]
    verbs = ["create", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "tfdrift-operator" {
  metadata {name = "tfdrift-operator"}
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = kubernetes_cluster_role.tfdrift-operator.metadata[0].name
  }

  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.tfdrift-operator.metadata[0].name
    namespace = kubernetes_namespace.tfdrift-operator.metadata[0].name
  }
}

resource "kubernetes_deployment" "tfdrift-operator" {
  metadata {
    name = "tfdrift-operator"
    namespace = kubernetes_namespace.tfdrift-operator.metadata[0].name
    labels = {app = "tfdrift-operator"}
  }

  spec {
    replicas = 1
    selector {match_labels = {app = "tfdrift-operator"}}

    template {
      metadata {labels = {app = "tfdrift-operator"}}

      spec {
        service_account_name = kubernetes_service_account.tfdrift-operator.metadata[0].name
        
        container {
          name = "manager"
          image = "jinbi/tfdrift-operator:v0.1.0"
        }
      }
    }
  }
}
