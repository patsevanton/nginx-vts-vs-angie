data "kubernetes_nodes" "nodes" {
  depends_on = [yandex_kubernetes_node_group.k8s-node-group]
}

locals {
  # Внутренний IP первой ноды K8s (NodePort backend'ов слушает на всех нодах)
  node_addresses       = data.kubernetes_nodes.nodes.nodes[0].status[0].addresses
  k8s_node_internal_ip = [for a in local.node_addresses : a.address if a.type == "InternalIP"][0]

  # Публичный адрес vlinsert для vector на VM. Берётся из текущего IP балансировщика,
  # чтобы при пересоздании IP Terraform'ом cloud-init всегда получал актуальный host.
  vlinsert_addr = "vlinsert.${yandex_vpc_address.addr.external_ipv4_address[0].address}.sslip.io:80"

  # 3 раздела бенчмарка: Low / Medium / High.
  # Каждый раздел = 2 VM (nginx-vts + angie) + 2 backend'а (NodePort) + 1 k6-джоба на вариант.
  # Все 6 VM поднимаются одновременно — разделы идут параллельно, без пересоздания VM.
  # nodeport_base задаёт стартовый NodePort раздела (шаг 2): low=30085, medium=30087, high=30089.
  #   - <base>     -> backend-<variant>-<section>-1
  #   - <base>+1   -> backend-<variant>-<section>-2
  benchmark_sections = {
    low = {
      max_vus    = 100
      cores      = 2
      memory     = 4
      nodeport_1 = 30085
      nodeport_2 = 30086
    }
    medium = {
      max_vus    = 200
      cores      = 4
      memory     = 8
      nodeport_1 = 30087
      nodeport_2 = 30088
    }
    high = {
      max_vus    = 300
      cores      = 4
      memory     = 8
      nodeport_1 = 30089
      nodeport_2 = 30090
    }
  }

  # 6 VM: для каждого раздела — по 2 (nginx-vts + angie).
  # variant nginx-vts использует docker-compose cloud-init, variant angie — deb-пакет.
  # key имеет вид "<variant>-<section>" (например "nginx-vts-low") — это имя ресурса и hostname VM.
  benchmark_vms = {
    for sv in setproduct(["nginx-vts", "angie"], keys(local.benchmark_sections)) :
    "${sv[0]}-${sv[1]}" => {
      variant    = sv[0]
      section    = sv[1]
      cores      = local.benchmark_sections[sv[1]].cores
      memory     = local.benchmark_sections[sv[1]].memory
      max_vus    = local.benchmark_sections[sv[1]].max_vus
      nodeport_1 = local.benchmark_sections[sv[1]].nodeport_1
      nodeport_2 = local.benchmark_sections[sv[1]].nodeport_2
    }
  }
}

resource "yandex_compute_instance" "benchmark_vm" {
  for_each = local.benchmark_vms

  name                      = each.key
  platform_id               = "standard-v2"
  network_acceleration_type = "software_accelerated"
  allow_stopping_for_update = true
  zone                      = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone

  resources {
    cores  = each.value.cores
    memory = each.value.memory
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
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = templatefile(
      each.value.variant == "nginx-vts"
      ? "${path.module}/benchmark/cloud-init/nginx-vts-docker.yaml"
      : "${path.module}/benchmark/cloud-init/angie.yaml",
      {
        instance_name  = each.key
        backend_addr_1 = "${local.k8s_node_internal_ip}:${each.value.nodeport_1}"
        backend_addr_2 = "${local.k8s_node_internal_ip}:${each.value.nodeport_2}"
        vlinsert_addr  = local.vlinsert_addr
      }
    )
  }
}

output "vm_nginx_vts_docker_ip" {
  description = "Публичный IP VM nginx-vts-high (для обратной совместимости со старыми командами)"
  value       = yandex_compute_instance.benchmark_vm["nginx-vts-high"].network_interface.0.nat_ip_address
}

output "vm_angie_ip" {
  description = "Публичный IP VM angie-high (для обратной совместимости со старыми командами)"
  value       = yandex_compute_instance.benchmark_vm["angie-high"].network_interface.0.nat_ip_address
}

output "vm_all_ips" {
  description = "Публичные IP всех 6 VM по ключу <variant>-<section>"
  value = {
    for k, v in yandex_compute_instance.benchmark_vm :
    k => v.network_interface.0.nat_ip_address
  }
}

output "angie_console_url" {
  value       = "http://angie-console.${yandex_compute_instance.benchmark_vm["angie-high"].network_interface.0.nat_ip_address}.sslip.io/console/"
  description = "Angie Console Light (Web UI мониторинга Angie high-раздела, домен через sslip.io из публичного IP VM Angie)"
}
