terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.219.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
  required_version = ">= 1.3"
}
