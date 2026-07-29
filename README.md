# Nginx-VTS vs Angie: сравнительный бенчмарк в Yandex Cloud

Инфраструктура как код (Terraform) и методика объективного сравнения двух популярных веб-прокси: **nginx с модулем VTS** (nginx-module-vts + nginx-vts-exporter) и **Angie** (форк nginx от «Веб-Сервера» с нативной поддержкой метрик Prometheus). Бенчмарк полностью воспроизводим: от развёртывания VM и Kubernetes-кластера до Grafana-дашборда с результатами.

## Ключевые результаты

| Метрика | nginx-vts-docker | Angie |
|---------|------------------|-------|
| Всего запросов (за 5м30с) | **679 316** | 655 973 |
| Средняя latency | **34.6 ms** | 36.2 ms |
| p95 latency | **103.2 ms** | 107.2 ms |
| Ошибки (rate) | 0.000003% | 0% |
| Макс. VU | 200 | 200 |

Вывод: при пиковой нагрузке до 200 виртуальных пользователей оба прокси показывают сопоставимую производительность. nginx-vts обработал на ~3.5% больше запросов с чуть меньшей latency, но потребовал сборки стороннего модуля и экспортера, тогда как Angie предоставил все метрики «из коробки».

## Архитектура

```
┌─────────────────┐     ┌──────────────────────────────────┐     ┌──────────────────────┐
│   Источник       │     │   Прокси (отдельные VM)          │     │   Приёмник (K8s)     │
│   трафика (k6)  │────▶│                                  │────▶│                      │
│   в K8s         │     │  VM1: nginx-vts (docker-compose) │     │  Backend (http-echo) │
│                 │     │    + nginx-vts-exporter :9913     │     │  в namespace         │
│                 │     │    + vector (логи → VictoriaLogs) │     │  "benchmark"         │
│                 │     │                                  │     │                      │
│                 │     │  VM2: angie                      │     │                      │
│                 │     │    + нативные метрики :80/metrics │     │                      │
│                 │     │    + vector (логи → VictoriaLogs) │     │                      │
└─────────────────┘     └──────────────────────────────────┘     └──────────────────────┘
          │                          │                                      │
          │                          ▼                                      │
          │               ┌──────────────────┐                              │
          │               │  VictoriaMetrics  │◀─ scrape /metrics обоих VM  │
          │               │  VictoriaLogs     │◀─ vector (newline_delimited) │
          │               │  Grafana          │                              │
          │               └──────────────────┘                              │
          └─────────────── k6 metrics ─────────────────────────────────────┘
```

## Сравниваемые варианты

| Вариант | Описание | Метрики |
|---------|----------|---------|
| **nginx-vts-docker** | NGINX + VTS модуль в Docker Compose | nginx-vts-exporter (`:9913/metrics`), vector (`:9598`) |
| **angie** | Angie, нативная установка (deb-пакет) | **встроенный** Prometheus (`:80/metrics` через `prometheus_all.conf`), API (`/api/`), vector (`:9598`) |

## Метрики для сравнения

| Категория | Метрика | Источник |
|-----------|---------|----------|
| **Клиентские** | RPS, latency (p50/p95/p99), TTFB, ошибки | k6 |
| **Прокси** | request count, bytes sent/received, status codes, active connections | nginx-vts-exporter / нативные метрики Angie |
| **Ресурсы** | CPU, MEM прокси | node-exporter / cAdvisor |
| **Логи** | events/s, processed bytes | vector internal metrics |

## Структура файлов

| Файл | Описание |
|------|----------|
| `versions.tf` | Провайдеры Terraform (Yandex Cloud, Helm, Kubernetes) |
| `net.tf` | VPC-сеть и подсети |
| `ip-dns.tf` | Статический IP балансировщика (публичные имена через **sslip.io**, собственная DNS-зона не нужна) |
| `k8s.tf` | K8s-кластер, ноды, Helm-релиз Ingress, генерация values с IP |
| `variables.tf` | Переменные (backend_nodeport, vlinsert_addr) |
| `benchmark-vms.tf` | 2 VM для nginx-vts-docker, angie |
| `benchmark-k8s.tf` | Namespace "benchmark", backend, ConfigMap с k6-скриптом |
| `benchmark-runners.tf` | k6 Job для каждого варианта |
| `values/victoriametrics-values.yaml` | Helm values: VictoriaMetrics + Grafana + vmagent (генерируется) |
| `values/victoria-logs-cluster-values.yaml` | Helm values: VictoriaLogs cluster + vlinsert ingress (генерируется) |
| `values/victoria-logs-collector-values.yaml` | Helm values: лог-коллектор |
| `values/*.tftpl` | Шаблоны values (рендерятся Terraform через `templatefile`) |
| `benchmark/k6/benchmark.js` | k6 скрипт нагрузки |
| `benchmark/cloud-init/*.yaml` | cloud-init для каждой VM |
| `benchmark/configs/*.conf` | nginx/angie конфигурации |
| `benchmark/configs/vector-*.toml` | vector конфигурации |
| `benchmark/grafana/benchmark-dashboard.json` | Grafana dashboard |

## Порядок развёртывания

### 1. Инициализация и деплой

```bash
terraform init
terraform plan
terraform apply
```

### 2. Получение доступа к K8s

После успешного `terraform apply` получаем доступ к кластеру (ID кластера возьмите из вывода `terraform output -raw k8s_cluster_credentials_command` или из консоли Yandex Cloud):

```bash
yc managed-kubernetes cluster get-credentials --id <cluster-id> --external --force
kubectl get nodes
```

### 3. Установка мониторинга и логирования

Установите Helm-чарты (VictoriaMetrics, VictoriaLogs). Values-файлы уже сгенерированы Terraform с актуальными IP (включая sslip.io-хосты):

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
  --namespace vlcollector --create-namespace \
  -f ./values/victoria-logs-collector-values.yaml
```

### 4. Применение benchmark-манифестов

```bash
# Namespace, backend, ConfigMap с k6-скриптом
kubectl apply -f benchmark/manifests/namespace.yaml
kubectl apply -f benchmark/manifests/backend-deployment.yaml -f benchmark/manifests/backend-service.yaml -f benchmark/manifests/k6-script-configmap.yaml -f benchmark/manifests/k6-env-configmap.yaml
```

### 5. Запуск бенчмарка

```bash
# Оба варианта параллельно
kubectl delete job k6-nginx-vts-docker k6-angie -n benchmark --ignore-not-found
kubectl apply -f benchmark/manifests/k6-nginx-vts-docker-job.yaml -f benchmark/manifests/k6-angie-job.yaml
```

### 6. Проверка результатов

```bash
# Статус k6 jobs
kubectl get jobs -n benchmark
kubectl get pods -n benchmark -l app=k6

# Логи k6 (итоговая сводка в конце)
kubectl logs job/k6-nginx-vts-docker -n benchmark
kubectl logs job/k6-angie -n benchmark

# Проверка сервисов на VM
for name_ip in "nginx-vts-docker:$(terraform output -raw vm_nginx_vts_docker_ip)" "angie:$(terraform output -raw vm_angie_ip)"; do
  name="${name_ip%%:*}"; ip="${name_ip##*:}"
  echo "=== $name ($ip) ==="
  echo -n "  HTTP: "; curl -s -o /dev/null -w "%{http_code}" "http://$ip/" || echo "FAIL"; echo ""
  echo -n "  Metrics: "; curl -s -o /dev/null -w "%{http_code}" "http://$ip:9913/metrics" 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" "http://$ip/metrics"; echo ""
  echo -n "  Vector: "; curl -s -o /dev/null -w "%{http_code}" "http://$ip:9598/metrics" || echo "N/A"; echo ""
done

# SSH на VM (пользователь ubuntu)
ssh ubuntu@$(terraform output -raw vm_nginx_vts_docker_ip)
ssh ubuntu@$(terraform output -raw vm_angie_ip)
```

### 7. Доступ к мониторингу

Хосты формируются по схеме `<сервис>.<LB_IP>.sslip.io` (IP балансировщика из `terraform output` / `kubectl get svc -n ingress-nginx`):

- **Grafana**: `http://grafana.<LB_IP>.sslip.io` (например, http://grafana.89.169.132.222.sslip.io)
- **VictoriaMetrics**: `http://vmselect.<LB_IP>.sslip.io`
- **VictoriaLogs**: `http://victorialogs.<LB_IP>.sslip.io`
- **vlinsert**: `http://vlinsert.<LB_IP>.sslip.io`

> sslip.io — бесплатный wildcard-DNS: `<anything>.<IP>.sslip.io` всегда резолвится в `<IP>`. Не требует делегирования доменной зоны.

## Метрики Angie «из коробки»

Angie собран с модулем `http_prometheus`. Для публикации метрик в конфиг добавлено:

```nginx
http {
    include /etc/angie/prometheus_all.conf;   # готовый шаблон "all"

    upstream backend {
        zone upstream_backend 64k;             # обязательно для сбора статистики upstream
        server <backend>:<port>;
        keepalive 64;
    }

    server {
        status_zone server_zone;               # обязательно для сбора статистики server
        ...
        location = /metrics { prometheus all; }  # нативный Prometheus endpoint
        location /api/    { api /status/; }      # REST API со статистикой
    }
}
```

Это даёт ~45 метрик `angie_*` (connections, server_zones, upstreams, slabs, caches и др.) без внешних экспортеров. vmagent scrape'ит `http://<angie_ip>/metrics`.

## Особенности доставки логов (vector → VictoriaLogs)

В cloud-init vector отправляет логи в vlinsert по HTTP. Два важных момента, найденных при отладке:

1. **`framing.method = "newline_delimited"`** — без него vector сериализует батч как JSON-**массив** (`[{...},{...}]`), а VictoriaLogs `/insert/jsonline` ожидает **по одному объекту на строку**. Иначе — `400 Bad Request` с ошибкой `value doesn't contain object; it contains array`.
2. **Корректный query-string** — параметры разделяются `&`, а не запятой: `?_stream_fields=instance&_msg_field=msg&_time_field=ts`.
3. **`batch.max_bytes`** — ограничение размера батча (~900KB) предотвращает `413 Payload Too Large` при всплеске логов под нагрузкой.

Remap-трансформы добавляют поле `instance` (stream label) и человекочитаемый `msg` (`METHOD URI STATUS`), поэтому в VictoriaLogs логи удобно фильтровать по `_stream:{instance="angie"}`.

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
