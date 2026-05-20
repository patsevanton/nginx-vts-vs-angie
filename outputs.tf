output "nlb_nginx_vts_external_ip" {
  value = [
    for listener in yandex_lb_network_load_balancer.nlb_nginx_vts.listener : [
      for addr in listener.external_address_spec : addr.address
    ]
  ][0][0]
}

output "nlb_angie_external_ip" {
  value = [
    for listener in yandex_lb_network_load_balancer.nlb_angie.listener : [
      for addr in listener.external_address_spec : addr.address
    ]
  ][0][0]
}

output "loadgen_vm_ip" {
  value = yandex_compute_instance.loadgen.network_interface[0].nat_ip_address
}

output "nginx_vts_vm_ip" {
  value = yandex_compute_instance.nginx_vts.network_interface[0].nat_ip_address
}

output "angie_vm_ip" {
  value = yandex_compute_instance.angie.network_interface[0].nat_ip_address
}

output "k8s_cluster_id" {
  value = yandex_kubernetes_cluster.main.id
}

output "k8s_cluster_endpoint" {
  value = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}
