resource "kubernetes_job_v1" "k6_nginx_vts_docker" {
  metadata {
    name      = "k6-nginx-vts-docker"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  spec {
    backoff_limit              = 0
    active_deadline_seconds    = 1800
    ttl_seconds_after_finished = 3600

    template {
      metadata {
        labels = {
          app = "k6"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "k6"
          image = "grafana/k6:0.56.0"

          args = [
            "run",
            "--env", "VARIANT=nginx-vts-docker",
            "--env", "TARGET_NGINX_VTS_DOCKER=${yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address}",
            "--env", "TARGET_NGINX_VTS=${yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address}",
            "--env", "TARGET_ANGIE=${yandex_compute_instance.angie.network_interface.0.nat_ip_address}",
            "/scripts/benchmark.js",
          ]

          volume_mount {
            name       = "k6-script"
            mount_path = "/scripts"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "k6-script"
          config_map {
            name = kubernetes_config_map_v1.k6_script.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.backend,
    kubernetes_service_v1.backend,
  ]

  wait_for_completion = false
}

resource "kubernetes_job_v1" "k6_nginx_vts" {
  metadata {
    name      = "k6-nginx-vts"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  spec {
    backoff_limit              = 0
    active_deadline_seconds    = 1800
    ttl_seconds_after_finished = 3600

    template {
      metadata {
        labels = {
          app = "k6"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "k6"
          image = "grafana/k6:0.56.0"

          args = [
            "run",
            "--env", "VARIANT=nginx-vts",
            "--env", "TARGET_NGINX_VTS_DOCKER=${yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address}",
            "--env", "TARGET_NGINX_VTS=${yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address}",
            "--env", "TARGET_ANGIE=${yandex_compute_instance.angie.network_interface.0.nat_ip_address}",
            "/scripts/benchmark.js",
          ]

          volume_mount {
            name       = "k6-script"
            mount_path = "/scripts"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "k6-script"
          config_map {
            name = kubernetes_config_map_v1.k6_script.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.backend,
    kubernetes_service_v1.backend,
  ]

  wait_for_completion = false
}

resource "kubernetes_job_v1" "k6_angie" {
  metadata {
    name      = "k6-angie"
    namespace = kubernetes_namespace_v1.benchmark.metadata[0].name
  }

  spec {
    backoff_limit              = 0
    active_deadline_seconds    = 1800
    ttl_seconds_after_finished = 3600

    template {
      metadata {
        labels = {
          app = "k6"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "k6"
          image = "grafana/k6:0.56.0"

          args = [
            "run",
            "--env", "VARIANT=angie",
            "--env", "TARGET_NGINX_VTS_DOCKER=${yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address}",
            "--env", "TARGET_NGINX_VTS=${yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address}",
            "--env", "TARGET_ANGIE=${yandex_compute_instance.angie.network_interface.0.nat_ip_address}",
            "/scripts/benchmark.js",
          ]

          volume_mount {
            name       = "k6-script"
            mount_path = "/scripts"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "k6-script"
          config_map {
            name = kubernetes_config_map_v1.k6_script.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.backend,
    kubernetes_service_v1.backend,
  ]

  wait_for_completion = false
}
