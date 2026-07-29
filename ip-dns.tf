resource "yandex_vpc_address" "addr" {
  name = "victorialogs-pip"

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.nginx-vts-vs-angie-a.zone
  }
}

# Публичный DNS не требуется: используются sslip.io-имена вида <сервис>.<LB_IP>.sslip.io
# (grafana, vmselect, victorialogs, vlinsert), которые резолвятся в IP балансировщика.
