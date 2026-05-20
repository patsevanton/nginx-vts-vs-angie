variable "yc_folder_id" {
  type        = string
  description = "Yandex Cloud folder ID (optional; defaults to client config)"
  default     = ""
}

variable "yc_zone" {
  type    = string
  default = "ru-central1-a"
}

variable "yc_region" {
  type    = string
  default = "ru-central1"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

variable "network_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "k8s_version" {
  type    = string
  default = "1.31"
}

variable "k8s_nodes_count" {
  type    = number
  default = 2
}

variable "k8s_nodes_cpu" {
  type    = number
  default = 4
}

variable "k8s_nodes_memory" {
  type    = number
  default = 8
}

variable "vm_loadgen_cpu" {
  type    = number
  default = 4
}

variable "vm_loadgen_memory" {
  type    = number
  default = 4
}

variable "vm_nginx_cpu" {
  type    = number
  default = 4
}

variable "vm_nginx_memory" {
  type    = number
  default = 4
}

variable "vm_angie_cpu" {
  type    = number
  default = 4
}

variable "vm_angie_memory" {
  type    = number
  default = 4
}
