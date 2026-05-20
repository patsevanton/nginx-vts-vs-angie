# ============================================================
# NLB for nginx-vts
# ============================================================
resource "yandex_lb_target_group" "nginx_vts" {
  name = "nginx-vts-tg"

  target {
    subnet_id = yandex_vpc_subnet.main.id
    address   = yandex_compute_instance.nginx_vts.network_interface[0].ip_address
  }
}

resource "yandex_lb_network_load_balancer" "nlb_nginx_vts" {
  name = "nlb-nginx-vts"
  type = "external"

  listener {
    name        = "http"
    port        = 80
    target_port = 80
    protocol    = "tcp"

    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.nginx_vts.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/health"
      }
    }
  }
}

# ============================================================
# NLB for angie
# ============================================================
resource "yandex_lb_target_group" "angie" {
  name = "angie-tg"

  target {
    subnet_id = yandex_vpc_subnet.main.id
    address   = yandex_compute_instance.angie.network_interface[0].ip_address
  }
}

resource "yandex_lb_network_load_balancer" "nlb_angie" {
  name = "nlb-angie"
  type = "external"

  listener {
    name        = "http"
    port        = 80
    target_port = 80
    protocol    = "tcp"

    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.angie.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/health"
      }
    }
  }
}
