resource "helm_release" "victoria_metrics" {
  name             = "victoria-metrics"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-k8s-stack"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [yandex_kubernetes_node_group.main]

  set = [
    {
      name  = "victoria-metrics-operator.enabled"
      value = "true"
      type  = "auto"
    },
    {
      name  = "grafana.enabled"
      value = "true"
      type  = "auto"
    },
    {
      name  = "grafana.adminPassword"
      value = "admin123"
      type  = "auto"
    },
    {
      name  = "vmsingle.spec.retentionPeriod"
      value = "30d"
      type  = "auto"
    },
    {
      name  = "vmsingle.spec.resources.requests.cpu"
      value = "500m"
      type  = "auto"
    },
    {
      name  = "vmsingle.spec.resources.requests.memory"
      value = "1Gi"
      type  = "auto"
    },
    {
      name  = "vmsingle.spec.resources.limits.cpu"
      value = "2"
      type  = "auto"
    },
    {
      name  = "vmsingle.spec.resources.limits.memory"
      value = "4Gi"
      type  = "auto"
    },
  ]

  timeout = 600
}

resource "helm_release" "victoria_logs" {
  name             = "victoria-logs"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-logs-k8s-stack"
  namespace        = "logging"
  create_namespace = true

  depends_on = [yandex_kubernetes_node_group.main]

  set = [
    {
      name  = "victoria-logs-operator.enabled"
      value = "true"
      type  = "auto"
    },
    {
      name  = "vlsingle.spec.retentionPeriod"
      value = "30d"
      type  = "auto"
    },
    {
      name  = "vlsingle.spec.resources.requests.cpu"
      value = "500m"
      type  = "auto"
    },
    {
      name  = "vlsingle.spec.resources.requests.memory"
      value = "1Gi"
      type  = "auto"
    },
    {
      name  = "vlsingle.spec.resources.limits.cpu"
      value = "2"
      type  = "auto"
    },
    {
      name  = "vlsingle.spec.resources.limits.memory"
      value = "4Gi"
      type  = "auto"
    },
  ]

  timeout = 600
}
