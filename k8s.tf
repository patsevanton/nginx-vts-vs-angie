data "yandex_client_config" "client" {}

resource "yandex_iam_service_account" "sa-k8s-editor" {
  name = "sa-k8s-editor"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-k8s-editor-permissions" {
  role      = "editor"
  folder_id = data.yandex_client_config.client.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.sa-k8s-editor.id}"
}

resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on = [
    yandex_iam_service_account.sa-k8s-editor,
    yandex_resourcemanager_folder_iam_member.sa-k8s-editor-permissions
  ]
}

resource "yandex_kubernetes_cluster" "nginx-vts-vs-angie" {
  name       = "nginx-vts-vs-angie"
  network_id = yandex_vpc_network.nginx-vts-vs-angie.id

  master {
    version = "1.32"
    zonal {
      zone      = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone
      subnet_id = yandex_vpc_subnet.nginx-vts-vs-angie-a.id
    }

    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.sa-k8s-editor.id
  node_service_account_id = yandex_iam_service_account.sa-k8s-editor.id

  release_channel = "STABLE"

  depends_on = [time_sleep.wait_sa]
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for the Managed Service for Kubernetes cluster"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.nginx-vts-vs-angie.id
  version     = "1.32"

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location { zone = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone }
    location { zone = yandex_vpc_subnet.nginx-vts-vs-angie-b.zone }
    location { zone = yandex_vpc_subnet.nginx-vts-vs-angie-d.zone }
  }

  instance_template {
    platform_id = "standard-v2"
    scheduling_policy {
      preemptible = true
    }

    network_interface {
      nat = true
      subnet_ids = [
        yandex_vpc_subnet.nginx-vts-vs-angie-a.id,
        yandex_vpc_subnet.nginx-vts-vs-angie-b.id,
        yandex_vpc_subnet.nginx-vts-vs-angie-d.id
      ]
    }

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-ssd"
      size = 33
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].cluster_ca_certificate

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].cluster_ca_certificate

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["k8s", "create-token"]
    command     = "yc"
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  chart            = "oci://cr.yandex/yc-marketplace/yandex-cloud/ingress-nginx/chart/ingress-nginx"
  version          = "4.13.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  depends_on = [
    yandex_kubernetes_cluster.nginx-vts-vs-angie
  ]

  values = [
    yamlencode({
      controller = {
        service = {
          loadBalancerIP = yandex_vpc_address.addr.external_ipv4_address[0].address
        }
        config = {
          log-format-escape-json = "true"
          log-format-upstream = trimspace(<<-EOT
            {"ts":"$time_iso8601","http":{"request_id":"$req_id","method":"$request_method","status_code":$status,"url":"$host$request_uri","host":"$host","uri":"$request_uri","request_time":$request_time,"user_agent":"$http_user_agent","protocol":"$server_protocol","trace_session_id":"$http_trace_session_id","server_protocol":"$server_protocol","content_type":"$sent_http_content_type","bytes_sent":"$bytes_sent"},"nginx":{"x-forward-for":"$proxy_add_x_forwarded_for","remote_addr":"$proxy_protocol_addr","http_referrer":"$http_referer"}}
          EOT
          )
        }
      }
    })
  ]
}

resource "helm_release" "victoriametrics" {
  name             = "victoriametrics"
  chart            = "victoria-metrics-k8s-stack"
  version          = "0.41.2"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://victoriametrics.github.io/helm-charts/"

  depends_on = [yandex_kubernetes_cluster.nginx-vts-vs-angie]

  values = [
    file("${path.module}/victoriametrics-values.yaml"),
    templatefile("${path.module}/benchmark/scrape-targets.yaml.tftpl", {
      nginx_vts_docker_ip = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
      nginx_vts_ip        = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
      angie_ip            = yandex_compute_instance.angie.network_interface.0.nat_ip_address
    }),
  ]
}

resource "helm_release" "victoria_logs_cluster" {
  name             = "victoria-logs-cluster"
  chart            = "victoria-logs-cluster"
  version          = "0.0.3"
  namespace        = "victoria-logs-cluster"
  create_namespace = true
  repository       = "https://victoriametrics.github.io/helm-charts/"

  depends_on = [yandex_kubernetes_cluster.nginx-vts-vs-angie]

  values = [
    file("${path.module}/victoria-logs-cluster-values.yaml")
  ]
}

resource "helm_release" "victoria_logs_collector" {
  name             = "victoria-logs-collector"
  chart            = "victoria-logs-collector"
  version          = "0.0.1"
  namespace        = "victoria-logs-cluster"
  create_namespace = false
  repository       = "https://victoriametrics.github.io/helm-charts/"

  depends_on = [
    yandex_kubernetes_cluster.nginx-vts-vs-angie,
    helm_release.victoria_logs_cluster,
  ]

  values = [
    file("${path.module}/victoria-logs-collector-values.yaml")
  ]
}

output "k8s_cluster_credentials_command" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.nginx-vts-vs-angie.id} --external --force"
}
