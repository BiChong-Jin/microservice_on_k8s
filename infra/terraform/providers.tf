terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

variable "kubeconfig_path" {
  type    = string
  default = "/home/ubuntu/.kube/config"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

