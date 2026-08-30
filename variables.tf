# Параметры бенчмарка (3 раздела × 2 варианта = 6 VM) заданы в locals.benchmark_sections
# в benchmark-vms.tf: max_vus, cores, memory, nodeports на каждый раздел.
variable "folder_id" {
  type        = string
  description = "Yandex Cloud folder id"
}
