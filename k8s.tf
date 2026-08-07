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
    version = "1.33"
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
  version     = "1.33"

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
    platform_id               = "standard-v2"
    network_acceleration_type = "software_accelerated"
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
      memory = 8
      cores  = 4
    }

    boot_disk {
      type = "network-ssd"
      size = 33
    }
  }
}

locals {
  ingress_nginx_values = templatefile("${path.module}/values/ingress-nginx-values.yaml.tftpl", {
    loadbalancer_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
  })

  victoriametrics_values = templatefile("${path.module}/values/victoriametrics-values.yaml.tftpl", {
    # IP всех 6 VM, разделённые по варианту: vm_ips (nginx-vts-*), angie_ips (angie-*)
    vm_ips    = { for k, v in yandex_compute_instance.benchmark_vm : k => v.network_interface.0.nat_ip_address if startswith(k, "nginx-vts-") }
    angie_ips = { for k, v in yandex_compute_instance.benchmark_vm : k => v.network_interface.0.nat_ip_address if startswith(k, "angie-") }
    lb_ip     = yandex_vpc_address.addr.external_ipv4_address[0].address
  })

  victoria_logs_cluster_values = templatefile("${path.module}/values/victoria-logs-cluster-values.yaml.tftpl", {
    lb_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
  })

  victoria_logs_collector_values = templatefile("${path.module}/values/victoria-logs-collector-values.yaml.tftpl", {})
}

resource "local_file" "ingress_nginx_values" {
  content         = local.ingress_nginx_values
  filename        = "${path.module}/values/ingress-nginx-values.yaml"
  file_permission = "0644"
}

resource "local_file" "victoriametrics_values" {
  content         = local.victoriametrics_values
  filename        = "${path.module}/values/victoriametrics-values.yaml"
  file_permission = "0644"
}

resource "local_file" "victoria_logs_cluster_values" {
  content         = local.victoria_logs_cluster_values
  filename        = "${path.module}/values/victoria-logs-cluster-values.yaml"
  file_permission = "0644"
}

resource "local_file" "victoria_logs_collector_values" {
  content         = local.victoria_logs_collector_values
  filename        = "${path.module}/values/victoria-logs-collector-values.yaml"
  file_permission = "0644"
}

provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "yc"
    args        = ["k8s", "create-token"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.nginx-vts-vs-angie.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "yc"
      args        = ["k8s", "create-token"]
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "oci://cr.yandex/yc-marketplace/yandex-cloud/ingress-nginx/chart"
  chart            = "ingress-nginx"
  version          = "4.13.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [local.ingress_nginx_values]

  depends_on = [
    yandex_kubernetes_cluster.nginx-vts-vs-angie,
    yandex_kubernetes_node_group.k8s-node-group,
  ]
}

output "k8s_cluster_credentials_command" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.nginx-vts-vs-angie.id} --external --force"
}

output "grafana_url" {
  description = "URL Grafana (сформирован через sslip.io из публичного IP балансировщика ingress-nginx)"
  value       = "http://grafana.${yandex_vpc_address.addr.external_ipv4_address[0].address}.sslip.io"
}

output "grafana_admin_user" {
  description = "Логин администратора Grafana (дефолт чарта victoria-metrics-k8s-stack)"
  value       = "admin"
}

output "grafana_admin_password_command" {
  description = "Команда для получения пароля администратора Grafana из Secret (пароль автогенерируется helm-чартом vmks при установке на шаге 3)"
  value       = "kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 -d && echo"
}

locals {
  benchmark_dashboard_configmap = templatefile("${path.module}/benchmark/templates/benchmark-dashboard-configmap.yaml.tftpl", {
    namespace      = "vmks"
    dashboard_json = file("${path.module}/benchmark/grafana/benchmark-dashboard.json")
  })
}

resource "local_file" "benchmark_dashboard_configmap" {
  content         = local.benchmark_dashboard_configmap
  filename        = "${path.module}/benchmark/manifests/benchmark-dashboard-configmap.yaml"
  file_permission = "0644"
}

output "kubectl_apply_dashboard_command" {
  description = "Команда для применения ConfigMap дашборда в namespace vmks (после helm install vmks на шаге 3)"
  value       = "kubectl apply -f ${local_file.benchmark_dashboard_configmap.filename}"
}
