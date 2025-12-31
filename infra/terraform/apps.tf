# --- recommendations ---
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
    port { port = 80 target_port = 5000 }
    type = "NodePort" # safest for kubeadm demo; switch to LB/Ingress later
  }
}

