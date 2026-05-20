# Инфраструктура Kubernetes в Yandex Cloud

Terraform-конфигурация для развёртывания Kubernetes-кластера в Yandex Cloud с компонентами мониторинга и логирования.

## Компоненты

| Компонент | Описание |
|-----------|----------|
| **Yandex Cloud K8s** | Управляемый Kubernetes-кластер (6 нод, 16 vCPU / 32 GB каждая) |
| **Ingress NGINX** | Ingress-контроллер (Helm-чарт из Yandex Cloud Marketplace) |
| **VictoriaMetrics K8s Stack** | Стек мониторинга (VictoriaMetrics + Grafana), совместим с PromQL |
| **VictoriaLogs** | Хранилище логов с поддержкой LogsQL в Grafana |
| **victoria-logs-collector** | Агент сбора логов (DaemonSet) |

## Структура файлов

| Файл | Описание |
|------|----------|
| `versions.tf` | Провайдеры Terraform (Yandex Cloud, Helm) |
| `net.tf` | VPC-сеть и подсети |
| `ip-dns.tf` | Статический IP и DNS-записи |
| `k8s.tf` | K8s-кластер, группа нод, Ingress NGINX |
| `victoriametrics-values.yaml` | Helm values для VictoriaMetrics K8s Stack |
| `victoria-logs-cluster-values.yaml` | Helm values для VictoriaLogs (cluster) |
| `victoria-logs-collector-values.yaml` | Helm values для victoria-logs-collector |

## Порядок развёртывания

### 1. Инфраструктура (Terraform)

```bash
terraform init
terraform plan
terraform apply
```

После применения:

```bash
yc managed-kubernetes cluster get-credentials --id <cluster_id> --external --force
```

### 2. VictoriaMetrics K8s Stack

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

helm upgrade --install vmks \
  oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack \
  --namespace vmks \
  --create-namespace \
  --wait \
  --version 0.70.0 \
  --timeout 15m \
  -f victoriametrics-values.yaml
```

Пароль администратора Grafana:

```bash
kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

### 3. VictoriaLogs (cluster)

```bash
helm upgrade --install victoria-logs-cluster vm/victoria-logs-cluster \
  --namespace victoria-logs-cluster \
  --create-namespace \
  --wait \
  --version 0.0.27 \
  --timeout 15m \
  -f victoria-logs-cluster-values.yaml
```

### 4. Victoria-logs-collector

```bash
helm upgrade --install victoria-logs-collector vm/victoria-logs-collector \
  --namespace victoria-logs-collector \
  --create-namespace \
  --wait \
  --version 0.2.9 \
  --timeout 15m \
  -f victoria-logs-collector-values.yaml
```

## Лицензия

См. [LICENSE](LICENSE).
