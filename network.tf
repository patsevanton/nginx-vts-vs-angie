resource "yandex_vpc_network" "main" {
  name = "nginx-bench-net"
}

resource "yandex_vpc_subnet" "main" {
  name           = "nginx-bench-subnet"
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
}

resource "yandex_vpc_security_group" "main" {
  name       = "nginx-bench-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    description    = "HTTP"
    port           = 80
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "SSH"
    port           = 22
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "NLB health checks"
    port           = 80
    protocol       = "TCP"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    description    = "Vector metrics"
    port           = 9598
    protocol       = "TCP"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    description    = "All internal"
    protocol       = "TCP"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  egress {
    description    = "All outbound"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "k8s" {
  name       = "k8s-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    description    = "All internal"
    protocol       = "TCP"
    v4_cidr_blocks = [var.network_cidr]
  }

  ingress {
    description    = "All internal UDP"
    protocol       = "UDP"
    v4_cidr_blocks = [var.network_cidr]
  }

  egress {
    description    = "All outbound"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
