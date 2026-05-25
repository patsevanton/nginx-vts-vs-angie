variable "backend_addr" {
  description = "Backend address for proxy upstream (host:port)"
  type        = string
  default     = "10.0.1.10:8080"
}

variable "vlinsert_addr" {
  description = "VictoriaLogs vlinsert address (host:port)"
  type        = string
  default     = "vlinsert.apatsev.org.ru:80"
}
