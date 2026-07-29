variable "backend_nodeport" {
  description = "NodePort of the benchmark backend service"
  type        = number
  default     = 30080
}

variable "vlinsert_addr" {
  description = "VictoriaLogs vlinsert address (host:port)"
  type        = string
  default     = "vlinsert.89.169.132.222.sslip.io:80"
}
