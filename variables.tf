variable "backend_nodeport" {
  description = "NodePort of the benchmark backend service"
  type        = number
  default     = 30080
}

variable "vlinsert_addr" {
  description = "VictoriaLogs vlinsert address (host:port)"
  type        = string
  default     = "vlinsert.apatsev.org.ru:80"
}
