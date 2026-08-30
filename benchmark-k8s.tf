locals {
  benchmark_namespace = "benchmark"

  benchmark_namespace_config = templatefile("${path.module}/benchmark/templates/namespace.yaml.tftpl", {
    namespace = local.benchmark_namespace
  })

  # 12 backend'ов: по 2 на каждую из 6 VM.
  # Имя: backend-<variant>-<section>-<n>, NodePort уникален на вариант:
  # nginx-vts -> базовые порты раздела (30085/86, 30087/88, 30089/90),
  # angie     -> базовые порты + 6 (30091/92, 30093/94, 30095/96).
  # Каждый backend — Deployment + Service (NodePort) из шаблона backend.yaml.tftpl.
  benchmark_backends = {
    for pair in flatten([
      for vm_name, vm in local.benchmark_vms : [
        { name = "backend-${vm_name}-1", node_port = vm.nodeport_1 },
        { name = "backend-${vm_name}-2", node_port = vm.nodeport_2 },
      ]
    ]) : pair.name => pair.node_port
  }

  benchmark_backend_configs = {
    for name, node_port in local.benchmark_backends :
    name => templatefile("${path.module}/benchmark/templates/backend.yaml.tftpl", {
      name      = name
      namespace = local.benchmark_namespace
      node_port = node_port
    })
  }

  benchmark_k6_script_config = templatefile("${path.module}/benchmark/templates/k6-script-configmap.yaml.tftpl", {
    namespace    = local.benchmark_namespace
    benchmark_js = file("${path.module}/benchmark/k6/benchmark.js")
  })

  # k6-env ConfigMap: 6 ключей TARGET_<VARIANT>_<SECTION> (верхний регистр, - на _) -> IP VM.
  benchmark_k6_targets = {
    for k, v in yandex_compute_instance.benchmark_vm :
    upper(replace(k, "-", "_")) => v.network_interface.0.nat_ip_address
  }

  benchmark_k6_env_config = templatefile("${path.module}/benchmark/templates/k6-env-configmap.yaml.tftpl", {
    namespace = local.benchmark_namespace
    targets   = local.benchmark_k6_targets
  })
}

resource "local_file" "benchmark_namespace" {
  content         = local.benchmark_namespace_config
  filename        = "${path.module}/benchmark/manifests/namespace.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_backends" {
  for_each = local.benchmark_backend_configs

  content         = each.value
  filename        = "${path.module}/benchmark/manifests/${each.key}.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_k6_script" {
  content         = local.benchmark_k6_script_config
  filename        = "${path.module}/benchmark/manifests/k6-script-configmap.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_k6_env" {
  content         = local.benchmark_k6_env_config
  filename        = "${path.module}/benchmark/manifests/k6-env-configmap.yaml"
  file_permission = "0644"
}

output "kubectl_apply_benchmark_command" {
  value = <<-EOT
    kubectl apply -f ${local_file.benchmark_namespace.filename}
    kubectl apply -f ${join(" -f ", [for k, v in local.benchmark_backend_configs : local_file.benchmark_backends[k].filename])} -f ${local_file.benchmark_k6_script.filename} -f ${local_file.benchmark_k6_env.filename}
  EOT
}
