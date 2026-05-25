locals {
  benchmark_k6_nginx_vts_docker_config = templatefile("${path.module}/benchmark/templates/k6-job.yaml.tftpl", {
    namespace                = local.benchmark_namespace
    variant                  = "nginx-vts-docker"
    target_nginx_vts_docker  = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    target_nginx_vts         = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
    target_angie             = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  })

  benchmark_k6_nginx_vts_config = templatefile("${path.module}/benchmark/templates/k6-job.yaml.tftpl", {
    namespace                = local.benchmark_namespace
    variant                  = "nginx-vts"
    target_nginx_vts_docker  = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    target_nginx_vts         = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
    target_angie             = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  })

  benchmark_k6_angie_config = templatefile("${path.module}/benchmark/templates/k6-job.yaml.tftpl", {
    namespace                = local.benchmark_namespace
    variant                  = "angie"
    target_nginx_vts_docker  = yandex_compute_instance.nginx-vts-docker.network_interface.0.nat_ip_address
    target_nginx_vts         = yandex_compute_instance.nginx-vts.network_interface.0.nat_ip_address
    target_angie             = yandex_compute_instance.angie.network_interface.0.nat_ip_address
  })
}

resource "local_file" "benchmark_k6_nginx_vts_docker" {
  content         = local.benchmark_k6_nginx_vts_docker_config
  filename        = "${path.module}/benchmark/manifests/k6-nginx-vts-docker-job.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_k6_nginx_vts" {
  content         = local.benchmark_k6_nginx_vts_config
  filename        = "${path.module}/benchmark/manifests/k6-nginx-vts-job.yaml"
  file_permission = "0644"
}

resource "local_file" "benchmark_k6_angie" {
  content         = local.benchmark_k6_angie_config
  filename        = "${path.module}/benchmark/manifests/k6-angie-job.yaml"
  file_permission = "0644"
}

resource "null_resource" "kubectl_apply_k6_jobs" {
  triggers = {
    k6_nginx_vts_docker_hash = sha256(local.benchmark_k6_nginx_vts_docker_config)
    k6_nginx_vts_hash        = sha256(local.benchmark_k6_nginx_vts_config)
    k6_angie_hash            = sha256(local.benchmark_k6_angie_config)
  }

  depends_on = [
    null_resource.kubectl_apply_benchmark,
    local_file.benchmark_k6_nginx_vts_docker,
    local_file.benchmark_k6_nginx_vts,
    local_file.benchmark_k6_angie,
  ]

  provisioner "local-exec" {
    command = <<-EOF
      kubectl apply \
        -f ${local_file.benchmark_k6_nginx_vts_docker.filename} \
        -f ${local_file.benchmark_k6_nginx_vts.filename} \
        -f ${local_file.benchmark_k6_angie.filename} \
        --kubeconfig ${local.kubeconfig_path}
    EOF
  }
}
