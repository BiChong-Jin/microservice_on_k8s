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
  default = "/etc/kubernetes/admin.conf"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

