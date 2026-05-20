resource "yandex_vpc_address" "addr" {
  name = "victorialogs-pip"

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.strimzi-a.zone
  }
}

resource "yandex_dns_zone" "apatsev-org-ru" {
  name = "apatsev-org-ru-zone"

  zone   = "apatsev.org.ru."
  public = true

  private_networks = [yandex_vpc_network.strimzi.id]
}

resource "yandex_dns_recordset" "grafana" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "grafana.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "victorialogs" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "victorialogs.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "victoriametrics" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "vmselect.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "chaos_dashboard" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "chaos-dashboard.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "kafka_ui" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id
  name    = "kafka-ui.apatsev.org.ru."
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}
