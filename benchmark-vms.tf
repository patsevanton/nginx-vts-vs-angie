data "kubernetes_nodes" "nodes" {
  depends_on = [yandex_kubernetes_node_group.k8s-node-group]
}

locals {
  # Внутренний IP первой ноды K8s (NodePort backend'ов слушает на всех нодах)
  node_addresses       = data.kubernetes_nodes.nodes.nodes[0].status[0].addresses
  k8s_node_internal_ip = [for a in local.node_addresses : a.address if a.type == "InternalIP"][0]
  # Раздельные backend'ы для каждого прокси: 2 NodePort на vts, 2 NodePort на angie.
  # Каждый прокси балансирует через upstream с 2 server'ами -> в метриках upstream видно 2 peer'а.
  backend_addr_vts_1   = "${local.k8s_node_internal_ip}:${var.backend_nodeport_vts_1}"
  backend_addr_vts_2   = "${local.k8s_node_internal_ip}:${var.backend_nodeport_vts_2}"
  backend_addr_angie_1 = "${local.k8s_node_internal_ip}:${var.backend_nodeport_angie_1}"
  backend_addr_angie_2 = "${local.k8s_node_internal_ip}:${var.backend_nodeport_angie_2}"
  # Публичный адрес vlinsert для vector на VM. Берём из текущего IP балансировщика,
  # чтобы при пересоздании IP Terraform'ом cloud-init всегда получал актуальный host.
  vlinsert_addr        = "vlinsert.${yandex_vpc_address.addr.external_ipv4_address[0].address}.sslip.io:80"
}

resource "yandex_compute_instance" "nginx-vts-docker" {
  name                      = "nginx-vts-docker"
  platform_id               = "standard-v2"
  network_acceleration_type = "software_accelerated"
  allow_stopping_for_update = true
  zone                      = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone

  resources {
    cores  = 4
    memory = 8
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = "fd806c8slu9j1pa87msc"
      size     = 30
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.nginx-vts-vs-angie-a.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = templatefile("${path.module}/benchmark/cloud-init/nginx-vts-docker.yaml", {
      backend_addr_1 = local.backend_addr_vts_1
      backend_addr_2 = local.backend_addr_vts_2
      vlinsert_addr  = local.vlinsert_addr
    })
  }
}

resource "yandex_compute_instance" "angie" {
  name                      = "angie"
  platform_id               = "standard-v2"
  network_acceleration_type = "software_accelerated"
  allow_stopping_for_update = true
  zone                      = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone

  resources {
    cores  = 4
    memory = 8
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = "fd806c8slu9j1pa87msc"
      size     = 30
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.nginx-vts-vs-angie-a.id
    nat       = true
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = templatefile("${path.module}/benchmark/cloud-init/angie.yaml", {
      backend_addr_1 = local.backend_addr_angie_1
      backend_addr_2 = local.backend_addr_angie_2
      vlinsert_addr  = local.vlinsert_addr
    })
  }
}

output "vm_nginx_vts_docker_ip" {
  value = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
}

output "vm_angie_ip" {
  value = yandex_compute_instance.angie.network_interface.0.nat_ip_address
}

output "angie_console_url" {
  value       = "http://angie-console.${yandex_compute_instance.angie.network_interface.0.nat_ip_address}.sslip.io/console/"
  description = "Angie Console Light (Web UI мониторинга Angie, домен через sslip.io из публичного IP VM Angie)"
}
