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
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = templatefile("${path.module}/benchmark/cloud-init/nginx-vts-docker.yaml", {
      backend_addr = var.backend_addr
      vlinsert_addr = var.vlinsert_addr
    })
  }
}

resource "yandex_compute_instance" "angie" {
  name        = "angie"
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
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = templatefile("${path.module}/benchmark/cloud-init/angie.yaml", {
      backend_addr = var.backend_addr
      vlinsert_addr = var.vlinsert_addr
    })
  }
}

output "vm_nginx_vts_docker_ip" {
  value = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
}

output "vm_angie_ip" {
  value = yandex_compute_instance.angie.network_interface.0.nat_ip_address
}
