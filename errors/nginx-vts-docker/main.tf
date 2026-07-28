# VM nginx-vts-docker — изолированный terraform-код, относящийся к ошибке.
# Из основного репозитория: benchmark-vms.tf, net.tf, variables.tf, versions.tf.
# Запуск: terraform init && terraform apply -target=yandex_compute_instance.nginx-vts-docker
# (требуются credentials Yandex Cloud: yc config / export YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID)

resource "yandex_vpc_network" "nginx-vts-vs-angie" {
  name = "nginx-vts-vs-angie"
}

resource "yandex_vpc_subnet" "nginx-vts-vs-angie-a" {
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.nginx-vts-vs-angie.id
}

variable "backend_addr" {
  description = "Backend address for proxy upstream (host:port)"
  type        = string
  default     = "10.0.1.10:8080"
}

variable "vlinsert_addr" {
  description = "VictoriaLogs vlinsert address (host:port)"
  type        = string
  default     = "vlinsert.apatsev.org.ru:80"
}

resource "yandex_compute_instance" "nginx-vts-docker" {
  name        = "nginx-vts-docker"
  platform_id = "standard-v2"
  zone        = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone

  resources {
    cores  = 2
    memory = 4
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
    user-data = templatefile("${path.module}/cloud-init/nginx-vts-docker.yaml", {
      backend_addr  = var.backend_addr
      vlinsert_addr = var.vlinsert_addr
    })
  }
}

output "vm_nginx_vts_docker_ip" {
  value = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
}
