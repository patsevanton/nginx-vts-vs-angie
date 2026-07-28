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
    version = "1.34"
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
  version     = "1.34"

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
    nginx_vts_docker_ip = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    angie_ip            = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  })

  victoria_logs_cluster_values = templatefile("${path.module}/values/victoria-logs-cluster-values.yaml.tftpl", {})

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
