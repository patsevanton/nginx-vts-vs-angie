resource "yandex_vpc_network" "nginx-vts-vs-angie" {
  name = "nginx-vts-vs-angie"
}

resource "yandex_vpc_subnet" "nginx-vts-vs-angie-a" {
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.nginx-vts-vs-angie.id
}

resource "yandex_vpc_subnet" "nginx-vts-vs-angie-b" {
  v4_cidr_blocks = ["10.0.2.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.nginx-vts-vs-angie.id
}

resource "yandex_vpc_subnet" "nginx-vts-vs-angie-d" {
  v4_cidr_blocks = ["10.0.3.0/24"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.nginx-vts-vs-angie.id
}
