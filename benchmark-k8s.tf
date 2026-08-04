locals {
  benchmark_namespace = "benchmark"

  benchmark_namespace_config = templatefile("${path.module}/benchmark/templates/namespace.yaml.tftpl", {
    namespace = local.benchmark_namespace
  })

  # 4 отдельных бэкенда: 2 для nginx-vts, 2 для angie.
  # Каждый бэкенд — собственный Deployment + Service (NodePort), params: name, node_port.
  benchmark_backends = {
    "backend-vts-1"   = var.backend_nodeport_vts_1
    "backend-vts-2"   = var.backend_nodeport_vts_2
    "backend-angie-1" = var.backend_nodeport_angie_1
    "backend-angie-2" = var.backend_nodeport_angie_2
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

  benchmark_k6_env_config = templatefile("${path.module}/benchmark/templates/k6-env-configmap.yaml.tftpl", {
    namespace                = local.benchmark_namespace
    target_nginx_vts_docker  = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    target_angie             = yandex_compute_instance.angie.network_interface.0.nat_ip_address
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
    kubectl apply -f ${local_file.benchmark_backends["backend-vts-1"].filename} -f ${local_file.benchmark_backends["backend-vts-2"].filename} -f ${local_file.benchmark_backends["backend-angie-1"].filename} -f ${local_file.benchmark_backends["backend-angie-2"].filename} -f ${local_file.benchmark_k6_script.filename} -f ${local_file.benchmark_k6_env.filename}
  EOT
}
