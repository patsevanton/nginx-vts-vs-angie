# Nginx-VTS vs Angie Benchmark

Terraform-конфигурация для сравнительного бенчмарка **nginx с VTS-модулем** и **Angie** в Yandex Cloud.

## Архитектура

```
┌─────────────────┐     ┌──────────────────────────────────┐     ┌──────────────────────┐
│   Источник       │     │   Прокси (отдельные VM)          │     │   Приёмник (K8s)     │
│   трафика (k6)  │────▶│                                  │────▶│                      │
│   в K8s         │     │  VM1: nginx-vts (docker-compose) │     │  Backend (http-echo) │
│                 │     │    + nginx-vts-exporter           │     │  в namespace         │
│                 │     │    + vector (логи → VictoriaLogs) │     │  "benchmark"         │
│                 │     │                                  │     │                      │
│                 │     │  VM2: nginx-vts (native)         │     │                      │
│                 │     │    + nginx-vts-exporter           │     │                      │
│                 │     │    + vector (логи → VictoriaLogs) │     │                      │
│                 │     │                                  │     │                      │
│                 │     │  VM3: angie                      │     │                      │
│                 │     │    + angie API /api/              │     │                      │
│                 │     │    + vector (логи → VictoriaLogs) │     │                      │
└─────────────────┘     └───────────────────��──────────────┘     └──────────────────────┘
         │                          │                                      │
         │                          ▼                                      │
         │               ┌──────────────────┐                              │
         │               │  VictoriaMetrics  │◀─ scrape nginx-vts-exporter  │
         │               │  VictoriaLogs     │◀─ vector logs                │
         │               │  Grafana          │                              │
         │               └──────────────────┘                              │
         └─────────────── k6 metrics ─────────────────────────────────────┘
```

## Сравниваемые варианты

| Вариант | Описание | Метрики |
|---------|----------|---------|
| **nginx-vts-docker** | NGINX + VTS модуль в Docker Compose | nginx-vts-exporter (`:9913`), stub_status, vector (`:9598`) |
| **nginx-vts** | NGINX + VTS модуль, нативная установка | nginx-vts-exporter (`:9913`), stub_status, vector (`:9598`) |
| **angie** | Angie, нативная установка | API (`/api/`), vector (`:9598`) |

## Метрики для сравнения

| Категория | Метрика | Источник |
|-----------|---------|----------|
| **Клиентские** | RPS, latency (p50/p95/p99), TTFB, ошибки | k6 |
| **Прокси** | request duration, bytes sent/received, status codes | nginx-vts-exporter / angie API |
| **Ресурсы** | CPU, MEM прокси | node-exporter / cAdvisor |
| **Логи** | events/s, processed bytes | vector metrics |

## Структура файлов

| Файл | Описание |
|------|----------|
| `versions.tf` | Провайдеры Terraform (Yandex Cloud, Helm, Kubernetes) |
| `net.tf` | VPC-сеть и подсети |
| `ip-dns.tf` | Статический IP, DNS-записи (Grafana, VictoriaLogs, VictoriaMetrics, vlinsert) |
| `k8s.tf` | K8s-кластер, ноды, Helm-релиз Ingress |
| `variables.tf` | Переменные (backend_addr, vlinsert_addr) |
| `benchmark-vms.tf` | 3 VM для nginx-vts-docker, nginx-vts, angie |
| `benchmark-k8s.tf` | Namespace "benchmark", backend, ConfigMap с k6-скриптом |
| `benchmark-runners.tf` | k6 Job для каждого варианта |
| `values/victoriametrics-values.yaml` | Helm values: VictoriaMetrics + Grafana + vmagent |
| `values/victoria-logs-cluster-values.yaml` | Helm values: VictoriaLogs cluster + vlinsert ingress |
| `values/victoria-logs-collector-values.yaml` | Helm values: лог-коллектор |
| `values/*.tftpl` | Шаблоны values (генерируются Terraform через `templatefile`) |
| `benchmark/k6/benchmark.js` | k6 скрипт нагрузки |
| `benchmark/cloud-init/*.yaml` | cloud-init для каждой VM |
| `benchmark/configs/*.conf` | nginx/angie конфигурации |
| `benchmark/configs/vector-*.toml` | vector конфигурации |
| `benchmark/grafana/benchmark-dashboard.json` | Grafana dashboard |
| `Makefile` | Утилиты для запуска бенчмарка |

## Порядок развёртывания

### 1. Инициализация и деплой

```bash
terraform init
terraform plan
terraform apply
```

### 2. Получение доступа к K8s

После успешного `terraform apply` получаем доступ к кластеру:

```bash
yc managed-kubernetes cluster get-credentials --id $(terraform output -raw k8s_cluster_id) --external --force
kubectl get nodes
```

### 3. Установка мониторинга и логирования

Установите Helm-чарты (VictoriaMetrics, VictoriaLogs):

```bash
# Добавление Helm-репозитория
helm repo add victoriametrics https://victoriametrics.github.io/helm-charts/
helm repo update

# VictoriaMetrics (k8s-stack: vmoperator, vmagent, vmselect, vminsert, Grafana)
helm upgrade --install vmks \
  victoriametrics/victoria-metrics-k8s-stack \
  --version 0.87.0 \
  --namespace vmks --create-namespace \
  -f ./values/victoriametrics-values.yaml

# VictoriaLogs cluster
helm upgrade --install vlcluster \
  victoriametrics/victoria-logs-cluster \
  --version 0.2.8 \
  --namespace vlcluster --create-namespace \
  -f ./values/victoria-logs-cluster-values.yaml

# VictoriaLogs collector (сбор логов с подов)
helm upgrade --install vlcollector \
  victoriametrics/victoria-logs-collector \
  --version 0.3.7 \
  --namespace vlcollector \
  -f ./values/victoria-logs-collector-values.yaml
```

### 4. Применение benchmark-манифестов

```bash
# Namespace, backend, ConfigMap с k6-скриптом
kubectl apply -f benchmark/manifests/namespace.yaml
kubectl apply -f benchmark/manifests/backend-deployment.yaml -f benchmark/manifests/backend-service.yaml -f benchmark/manifests/k6-script-configmap.yaml -f benchmark/manifests/k6-env-configmap.yaml

# k6 Jobs
kubectl apply -f benchmark/manifests/k6-nginx-vts-docker-job.yaml -f benchmark/manifests/k6-nginx-vts-job.yaml -f benchmark/manifests/k6-angie-job.yaml
```

### 5. Запуск бенчмарка

```bash
# Все три варианта последовательно
make benchmark

# Или по одному
make run-k6-nginx-vts-docker
make run-k6-nginx-vts
make run-k6-angie
```

### 6. Проверка результатов

```bash
# Статус k6 jobs
make benchmark-status

# Логи k6
make benchmark-logs

# Проверка сервисов на VM
make check-services

# SSH на VM
make vm-ssh-nginx-vts-docker
make vm-ssh-nginx-vts
make vm-ssh-angie
```

### 7. Доступ к мониторингу

- **Grafana**: `http://grafana.apatsev.org.ru`
- **VictoriaMetrics**: `http://vmselect.apatsev.org.ru`
- **VictoriaLogs**: `http://victorialogs.apatsev.org.ru`

## k6 сценарий нагрузки

1. **Warmup**: 10 VU × 30 сек
2. **Ramp-up**: 0 → 50 VU за 30 сек
3. **Sustained**: 50 VU × 60 сек
4. **Peak ramp**: 50 → 100 VU за 30 сек
5. **Peak sustained**: 100 VU × 60 сек
6. **High peak ramp**: 100 → 200 VU за 30 сек
7. **High peak sustained**: 200 VU × 60 сек
8. **Cooldown**: 200 → 0 VU за 30 сек

## Очистка

```bash
terraform destroy
```
