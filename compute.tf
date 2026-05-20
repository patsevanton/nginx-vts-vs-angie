data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# ============================================================
# VM1: Load Generator (hey)
# ============================================================
resource "yandex_compute_instance" "loadgen" {
  name        = "loadgen"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores  = var.vm_loadgen_cpu
    memory = var.vm_loadgen_memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.main.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init/loadgen.yaml", {
      ssh_public_key = var.ssh_public_key
    })
  }
}

# ============================================================
# VM2: nginx-vts in Docker + Vector
# ============================================================
resource "yandex_compute_instance" "nginx_vts" {
  name        = "nginx-vts"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores  = var.vm_nginx_cpu
    memory = var.vm_nginx_memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 30
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.main.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init/nginx-vts.yaml", {
      ssh_public_key       = var.ssh_public_key
      victorialogs_endpoint = "localhost:9428" # Will be updated after k8s deploy
    })
  }
}

# ============================================================
# VM3: Angie (bare metal) + Vector
# ============================================================
resource "yandex_compute_instance" "angie" {
  name        = "angie"
  platform_id = "standard-v3"
  zone        = var.yc_zone

  resources {
    cores  = var.vm_angie_cpu
    memory = var.vm_angie_memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 30
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.main.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init/angie.yaml", {
      ssh_public_key       = var.ssh_public_key
      victorialogs_endpoint = "localhost:9428" # Will be updated after k8s deploy
    })
  }
}
