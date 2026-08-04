variable "backend_nodeport_vts_1" {
  description = "NodePort of the nginx-vts backend #1"
  type        = number
  default     = 30081
}

variable "backend_nodeport_vts_2" {
  description = "NodePort of the nginx-vts backend #2"
  type        = number
  default     = 30082
}

variable "backend_nodeport_angie_1" {
  description = "NodePort of the angie backend #1"
  type        = number
  default     = 30083
}

variable "backend_nodeport_angie_2" {
  description = "NodePort of the angie backend #2"
  type        = number
  default     = 30084
}

# vlinsert_addr не задаётся переменной — он вычисляется в locals из текущего
# публичного IP балансировщика (yandex_vpc_address.addr), чтобы cloud-init
# всегда получал актуальный адрес. hardcoded default убран: при пересоздании
# статического IP Terraform'ом старый адрес становился недействительным,
# и vector на VM шлёл логи в никуда.
