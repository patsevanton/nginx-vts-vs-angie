resource "yandex_kubernetes_cluster" "main" {
  name        = "nginx-bench-k8s"
  description = "K8s cluster for VictoriaMetrics and VictoriaLogs"
  network_id  = yandex_vpc_network.main.id

  master {
    version = var.k8s_version
    zonal {
      zone      = var.yc_zone
      subnet_id = yandex_vpc_subnet.main.id
    }
    public_ip            = true
    security_group_ids   = [yandex_vpc_security_group.k8s.id]
  }

  service_account_id      = yandex_iam_service_account.k8s_sa.id
  node_service_account_id = yandex_iam_service_account.k8s_sa.id

  depends_on = [
    yandex_resourcemanager_folder_iam_binding.k8s_editor,
    yandex_resourcemanager_folder_iam_binding.k8s_images_puller,
  ]
}

resource "yandex_iam_service_account" "k8s_sa" {
  name        = "k8s-sa"
  description = "Service account for K8s cluster"
}

resource "yandex_resourcemanager_folder_iam_binding" "k8s_editor" {
  folder_id = local.yc_folder_id
  role      = "editor"
  members   = ["serviceAccount:${yandex_iam_service_account.k8s_sa.id}"]
}

resource "yandex_resourcemanager_folder_iam_binding" "k8s_images_puller" {
  folder_id = local.yc_folder_id
  role      = "container-registry.images.puller"
  members   = ["serviceAccount:${yandex_iam_service_account.k8s_sa.id}"]
}

resource "yandex_kubernetes_node_group" "main" {
  cluster_id = yandex_kubernetes_cluster.main.id
  name       = "main-nodes"
  version    = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    resources {
      cores  = var.k8s_nodes_cpu
      memory = var.k8s_nodes_memory
    }

    boot_disk {
      type = "network-ssd"
      size = 64
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.main.id]
      nat        = true
    }

    metadata = {
      ssh-keys = "ubuntu:${var.ssh_public_key}"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.k8s_nodes_count
    }
  }

  allocation_policy {
    location {
      zone = var.yc_zone
    }
  }
}
