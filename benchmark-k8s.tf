locals {
  benchmark_namespace = "benchmark"

  benchmark_namespace_config = templatefile("${path.module}/benchmark/templates/namespace.yaml.tftpl", {
    namespace = local.benchmark_namespace
  })

  benchmark_backend_deployment_config = templatefile("${path.module}/benchmark/templates/backend-deployment.yaml.tftpl", {
    namespace = local.benchmark_namespace
  })

  benchmark_backend_service_config = templatefile("${path.module}/benchmark/templates/backend-service.yaml.tftpl", {
    namespace = local.benchmark_namespace
  })

  benchmark_k6_script_config = templatefile("${path.module}/benchmark/templates/k6-script-configmap.yaml.tftpl", {
    namespace    = local.benchmark_namespace
    benchmark_js = file("${path.module}/benchmark/k6/benchmark.js")
  })

  benchmark_k6_env_config = templatefile("${path.module}/benchmark/templates/k6-env-configmap.yaml.tftpl", {
    namespace                = local.benchmark_namespace
    target_nginx_vts_docker  = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    target_nginx_vts         = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
    target_angie             = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  })
}

resource "local_file" "benchmark_namespace" {
  content         = local.benchmark_namespace_config
  filename        = "${path.module}/benchmark/manifests/namespace.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_backend_deployment" {
  content         = local.benchmark_backend_deployment_config
  filename        = "${path.module}/benchmark/manifests/backend-deployment.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_backend_service" {
  content         = local.benchmark_backend_service_config
  filename        = "${path.module}/benchmark/manifests/backend-service.yaml"
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

resource "null_resource" "kubectl_apply_benchmark" {
  triggers = {
    namespace_hash     = sha256(local.benchmark_namespace_config)
    deployment_hash    = sha256(local.benchmark_backend_deployment_config)
    service_hash       = sha256(local.benchmark_backend_service_config)
    k6_script_hash     = sha256(local.benchmark_k6_script_config)
    k6_env_hash        = sha256(local.benchmark_k6_env_config)
  }

  depends_on = [
    yandex_kubernetes_cluster.nginx-vts-vs-angie,
    local_file.benchmark_namespace,
    local_file.benchmark_backend_deployment,
    local_file.benchmark_backend_service,
    local_file.benchmark_k6_script,
    local_file.benchmark_k6_env,
    local_file.kubeconfig,
  ]

  provisioner "local-exec" {
    command = <<-EOF
      kubectl apply -f ${local_file.benchmark_namespace.filename} \
        --kubeconfig ${local.kubeconfig_path} && \
      kubectl apply -f ${local_file.benchmark_backend_deployment.filename} \
        -f ${local_file.benchmark_backend_service.filename} \
        -f ${local_file.benchmark_k6_script.filename} \
        -f ${local_file.benchmark_k6_env.filename} \
        --kubeconfig ${local.kubeconfig_path}
    EOF
  }
}
