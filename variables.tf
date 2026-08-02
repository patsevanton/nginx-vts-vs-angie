variable "backend_nodeport" {
  description = "NodePort of the benchmark backend service"
  type        = number
  default     = 30080
}

# vlinsert_addr не задаётся переменной — он вычисляется в locals из текущего
# публичного IP балансировщика (yandex_vpc_address.addr), чтобы cloud-init
# всегда получал актуальный адрес. hardcoded default убран: при пересоздании
# статического IP Terraform'ом старый адрес становился недействительным,
# и vector на VM шлёл логи в никуда.
