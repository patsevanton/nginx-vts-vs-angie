resource "kubernetes_namespace_v1" "benchmark" {
  metadata {
    name = "benchmark"
  }

  depends_on = [yandex_kubernetes_cluster.nginx-vts-vs-angie]
}

resource "kubernetes_deployment_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
    labels = {
      app = "backend"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "backend"
        }
      }

      spec {
        container {
          name  = "backend"
          image = "hashicorp/http-echo:0.2.3"

          args = [
            "-text=OK",
            "-listen=:8080",
          ]

          port {
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  spec {
    selector = {
      app = "backend"
    }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_config_map_v1" "k6_script" {
  metadata {
    name      = "k6-script"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  data = {
    "benchmark.js" = file("${path.module}/benchmark/k6/benchmark.js")
  }
}

resource "kubernetes_config_map_v1" "k6_env" {
  metadata {
    name      = "k6-env"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  data = {
    TARGET_NGINX_VTS_DOCKER = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    TARGET_NGINX_VTS        = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
    TARGET_ANGIE            = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  }
}
