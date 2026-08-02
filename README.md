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

## Отличительные features каждого варианта

Два варианта сопоставимы по производительности (см. «Ключевые результаты»), но принципиально различаются способом получения метрик, поставкой и наличием визуальной консоли.

### nginx-vts-docker

| Feature | Реализация |
|---|---|
| Базовый сервер | Голый **nginx 1.28** из исходников (`nginx.org/download/nginx-1.28.0.tar.gz`) |
| Модуль метрик | **Сторонний** `nginx-module-vts` v0.2.5 — собирается как dynamic-модуль (`--add-dynamic-module`) и подключается через `load_module` |
| Экспорт в Prometheus | **Внешний sidecar-экспортёр** `nginx-vts-exporter` v0.10.8 (отдельный Go-бинарник, слушает `:9913`), парсит JSON-статус с `http://127.0.0.1:80/status` |
| Поставка | **Docker Compose** — nginx собирается из Dockerfile, рядом контейнер vector; всё изолированно, но образ нужно собирать (`docker compose up -d --build`) |
| Endpoint статуса | `/status` — JSON (формат VTS) |
| Web-консоль | **Нет** — только JSON `/status` и текстовый `/stub_status` |
| Количество метрик | ~12 метрик `nginx_*` (server, upstream, cache) |
| Зависимости | Docker, git, build-essential, libpcre3-dev, zlib1g-dev, libssl-dev — для сборки модуля на VM |
| Обновление | Пересборка Docker-образа при выходе новой версии nginx/VTS-модуля |

> Ключевой недостаток — сторонний модуль VTS [не обновлялся с 2021 года](https://github.com/vozlt/nginx-module-vts), его нужно собирать под каждую версию nginx, а экспортёр — отдельный процесс, который может упасть независимо от nginx.

### angie

| Feature | Реализация |
|---|---|
| Базовый сервер | **Angie** — форк nginx от «Веб-Сервера», устанавливается deb-пакетом из репозитория `download.angie.software` |
| Модуль метрик | **Нативный** `http_prometheus` — входит в поставку Angie, подключается одной строкой `include /etc/angie/prometheus_all.conf` |
| Экспорт в Prometheus | **Без отдельного экспортёра** — метрики отдаёт сам Angie на `:80/metrics` (`prometheus all;`), отдельный процесс не нужен |
| Поставка | **deb-пакет** (`apt-get install angie`) — без Docker, без сборки, без управления зависимостями компилятора |
| Endpoint статуса | `/api/` — REST API (`api /status/`, JSON-дерево `/status/connections/`, `/status/http/server_zones/`, `/status/http/upstreams/` и т.д.), `/metrics` — Prometheus, `/status.html` — `stub_status` |
| Web-консоль | **[Console Light](https://angie.software/angie/docs/configuration/monitoring/)** — отдельный пакет `angie-console-light`, ставится через `apt-get install angie-console-light`, отдаётся на `/console/` через `alias /usr/share/angie-console-light/html/`. В реальном времени показывает connections, server zones, upstreams, caches, SSL; в бенчмарке устанавливается в `cloud-init/angie.yaml` (доступна по `http://<angie_ip>/console/`) |
| Количество метрик | ~45 метрик `angie_*` (connections, server_zones, upstreams, slabs, caches и др.) «из коробки» |
| Сбор статистики | Через shared-memory зоны: `zone upstream_backend 64k` в `upstream` и `status_zone server_zone` в `server` — обязательны для сбора |
| Зависимости | Только deb-пакет angie + angie-console-light — всё из репозитория, без компиляции |
| Обновление | `apt-get upgrade angie angie-console-light` — обновление одной командой |

> Ключевое преимущество Angie — метрики «из коробки» (нативный Prometheus + REST API + визуальная Console Light) без сборки модулей и sidecar-экспортёров. Ключевое преимущество nginx-vts — независимость от форка (можно взять любой nginx и добавить модуль VTS).

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
  echo -n "  Status/API: "; curl -s -o /dev/null -w "%{http_code}" "http://$ip/status" 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" "http://$ip/api/"; echo ""
done

# Web-консоль Angie (Console Light) — открывается в браузере
# (после terraform apply с обновлённым cloud-init; HTTP 200 + HTML отдаёт Console Light,
#  а не backend — последний отвечает "OK" на любой путь через location /)
ANGIE_IP=$(terraform output -raw vm_angie_ip)
curl -s -o /dev/null -w "Angie Console Light: HTTP %{http_code}\n" "http://$ANGIE_IP/console/"
echo "Открыть в браузере: http://$ANGIE_IP/console/"

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

URL Grafana, логин и команда для получения пароля выводятся в `terraform output` (пароль автогенерируется helm-чартом `vmks` на шаге 3, поэтому Terraform возвращает команду `kubectl`, а не сам пароль):

```bash
terraform output grafana_url
terraform output grafana_admin_user
terraform output grafana_admin_password_command    # команда для получения пароля из Secret vmks-grafana
```

> Логин: `admin`. Пароль — из Secret `vmks-grafana` (ключ `admin-password`), извлекается одной командой из `terraform output grafana_admin_password_command`.

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

### Web-консоль Angie Console Light

Помимо API и метрик, Angie имеет визуальную консоль [Console Light](https://angie.software/angie/docs/configuration/monitoring/) — отдельный пакет `angie-console-light`, который в бенчмарке ставится через `apt-get install angie-console-light` в `cloud-init/angie.yaml`. Консоль отдаётся на `/console/`:

```nginx
location /console/ {
    auto_redirect on;
    alias /usr/share/angie-console-light/html/;
    index index.html;

    location /console/api/ {
        api /status/;
    }
}
```

Консоль доступна в браузере по `http://<angie_ip>/console/` (без аутентификации — в этом бенчмарке `auth_basic` намеренно не включён, т.к. IP VM публичный только на время замера; для production добавьте `auth_basic`). У nginx-vts аналога нет — только JSON `/status`.

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
