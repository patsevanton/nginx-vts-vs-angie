terraform {
  required_version = ">= 1.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.100"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
  }
}

provider "yandex" {
  zone = var.yc_zone
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.main.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}
