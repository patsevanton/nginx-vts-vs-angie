locals {
  # 6 k6-джоб: по одной на каждую VM (variant × section).
  # Каждая джоба бьёт в свою VM (target IP) со своим MAX_VUS.
  # variant/section/max_vus берутся из local.benchmark_vms, target — публичный IP VM.
  benchmark_k6_jobs = {
    for k, v in local.benchmark_vms :
    k => {
      variant = v.variant
      section = v.section
      max_vus = v.max_vus
      target  = yandex_compute_instance.benchmark_vm[k].network_interface.0.nat_ip_address
    }
  }

  benchmark_k6_job_configs = {
    for k, v in local.benchmark_k6_jobs :
    k => templatefile("${path.module}/benchmark/templates/k6-job.yaml.tftpl", {
      namespace = local.benchmark_namespace
      variant   = v.variant
      section   = v.section
      max_vus   = v.max_vus
      target    = v.target
    })
  }
}

resource "local_file" "benchmark_k6_job" {
  for_each = local.benchmark_k6_job_configs

  content         = each.value
  filename        = "${path.module}/benchmark/manifests/k6-${each.key}-job.yaml"
  file_permission = "0644"
}

output "kubectl_apply_k6_jobs_command" {
  value = <<-EOT
    kubectl apply -f ${join(" -f ", [for k, v in local.benchmark_k6_job_configs : local_file.benchmark_k6_job[k].filename])}
  EOT
}
