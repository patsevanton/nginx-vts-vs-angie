# Nginx-VTS vs Angie: сравнительный бенчмарк в Yandex Cloud

Инфраструктура как код (Terraform) и методика объективного сравнения двух популярных веб-прокси: **nginx с модулем VTS** (nginx-module-vts + nginx-vts-exporter) и **Angie** (форк nginx от «Веб-Сервера» с нативной поддержкой метрик Prometheus). Бенчмарк полностью воспроизводим: от развёртывания VM и Kubernetes-кластера до Grafana-дашборда с результатами.

> **Требование к версии Kubernetes:** бенчмарк проверен на **Managed Kubernetes 1.33** (release channel `STABLE`). В `k8s.tf` версия жёстко задана как `1.33` и для master, и для node group. Yandex Managed Kubernetes также поддерживает 1.32/1.34/1.35 (канал `RAPID`/`REGULAR`) — если хотите другую версию, измените `version` в `k8s.tf` (две позиции: `master.version` и `yandex_kubernetes_node_group.k8s-node-group.version`). На 1.32 и младше Helm-чарт `victoria-metrics-k8s-stack 0.88.0` может требовать более старых API-версий CRD.
>
> **Требование к версии чарта VictoriaMetrics:** используется `victoria-metrics-k8s-stack 0.88.0` — баг `config-reloader` на K8s 1.33 (VMAgent не перечитывал Secret со скрейп-конфигом при пересоздании VM/смене IP, скрейпы шли на устаревшие адреса, см. <https://github.com/VictoriaMetrics/helm-charts/issues/3136>) исправлен в этой версии. На более старых версиях чарта (0.87.0 и младше) использовать workaround: `kubectl rollout restart deployment vmagent-vm-stack -n vmks` после смены IP VM.

## Ключевые результаты

Бенчмарк разбит на **3 раздела** по уровню нагрузки и ресурсов VM. В каждом разделе ресурсы VM nginx-vts-docker и angie **одинаковые** — чтобы сравнивать прокси, а не железо. k6-сценарий один и тот же (warmup 10 VU × 30с + ramp 0→50→…→MAX_VUS→0 за 8м), меняется только пиковое значение VU (`MAX_VUS`).

| Раздел | MAX_VUS | Ресурсы VM (cores/RAM) | Сеть | Ожидаемое RPS |
|---|---|---|---|---|
| **Low**    | 100 | 2 c / 4 ГБ | software-accelerated | ~1500–2000 |
| **Medium** | 200 | 4 c / 8 ГБ | software-accelerated | ~3000–4000 |
| **High**   | 300 | 4 c / 8 ГБ | software-accelerated | ~4500–5500 |

> Конфигурация ресурсов и сети задаётся в `benchmark-vms.tf` (`resources`, `network_acceleration_type`), пиковое VU — через env `MAX_VUS` в `benchmark/templates/k6-job.yaml.tftpl`. Перед каждым разделом: `terraform apply` (обновить ресурсы VM) → дождаться cloud-init → health-check VM → запустить k6 jobs → собрать результаты. Подробная процедура — в шаге 5.

### Раздел 1: Low (100 VU, 2 c / 4 ГБ, software-accelerated network)

| Метрика | nginx-vts-docker | Angie |
|---------|------------------|-------|
| Всего запросов | _заполнить после прогона_ | _заполнить_ |
| Средняя latency | _заполнить_ | _заполнить_ |
| p95 latency | _заполнить_ | _заполнить_ |
| Ошибки (rate) | _заполнить_ | _заполнить_ |
| Макс. VU | 100 | 100 |

### Раздел 2: Medium (200 VU, 4 c / 8 ГБ, software-accelerated network)

| Метрика | nginx-vts-docker | Angie |
|---------|------------------|-------|
| Всего запросов | _заполнить_ | _заполнить_ |
| Средняя latency | _заполнить_ | _заполнить_ |
| p95 latency | _заполнить_ | _заполнить_ |
| Ошибки (rate) | _заполнить_ | _заполнить_ |
| Макс. VU | 200 | 200 |

### Раздел 3: High (300 VU, 4 c / 8 ГБ, software-accelerated network)

| Метрика | nginx-vts-docker | Angie |
|---------|------------------|-------|
| Всего запросов | 1,525,163 | 1,496,600 |
| Средняя latency (мс) | 28.98 | 30.03 |
| p95 latency (мс) | 100.74 | 110.32 |
| Max latency (мс) | 513.17 | 1506.91 |
| Ошибок | 0 | 0 |
| Макс. VU | 300 | 300 |

### Вывод

По результатам раздела High (300 VU, 4 c / 8 ГБ): nginx-vts-docker показал чуть лучшие результаты — на ~2% больше запросов (1,525,163 vs 1,496,600), на ~3.5% ниже средняя latency (28.98 мс vs 30.03 мс), на ~9% ниже p95 latency (100.74 мс vs 110.32 мс). Максимальная latency у nginx-vts-docker значительно ниже (513 мс vs 1507 мс). Оба варианта не допустили ни одной ошибки. Разница невелика — оба прокси хорошо справляются с нагрузкой 300 VU на 4 c / 8 ГБ.

## Архитектура

```
┌─────────────────┐     ┌──────────────────────────────────┐     ┌────────────────────────────────┐
│   Источник       │     │   Прокси (отдельные VM)          │     │   Приёмник (K8s)               │
│   трафика (k6)  │────▶│                                  │────▶│                                │
│   в K8s         │     │  VM1: nginx-vts (docker-compose) │     │  2 backend'а для nginx-vts:   │
│                 │     │    + nginx-vts-exporter :9913     │     │   backend-vts-1 (NodePort 30081)│
│                 │     │    + vector (логи → VictoriaLogs) │     │   backend-vts-2 (NodePort 30082)│
│                 │     │    upstream backend {            │     │   (http-echo, replicas: 1)      │
│                 │     │     server <node_ip>:30081;       │     │                                │
│                 │     │     server <node_ip>:30082;       │     │  2 backend'а для angie:        │
│                 │     │   }                              │     │   backend-angie-1 (NodePort 30083)│
│                 │     │                                  │     │   backend-angie-2 (NodePort 30084)│
│                 │     │  VM2: angie                      │     │   (http-echo, replicas: 1)      │
│                 │     │    + нативные метрики :80/metrics │     │                                │
│                 │     │    + vector (логи → VictoriaLogs) │     │  upstreamZones / peers:         │
│                 │     │    upstream backend {            │     │   2 peer'а на прокси            │
│                 │     │     server <node_ip>:30083;       │     │                                │
│                 │     │     server <node_ip>:30084;       │     │                                │
│                 │     │   }                              │     │                                │
└─────────────────┘     └──────────────────────────────────┘     └────────────────────────────────┘
          │                          │                                      │
          │                          ▼                                      │
          │               ┌──────────────────┐                              │
          │               │  VictoriaMetrics  │◀─ scrape /metrics обоих VM  │
          │               │  VictoriaLogs     │◀─ vector (newline_delimited) │
          │               │  Grafana          │                              │
          │               └──────────────────┘                              │
          └─────────────── k6 metrics ─────────────────────────────────────┘
```

Каждый прокси балансирует на **2 отдельных бэкенда** через upstream (round-robin): nginx-vts → `backend-vts-1` (NodePort 30081) + `backend-vts-2` (NodePort 30082), angie → `backend-angie-1` (NodePort 30083) + `backend-angie-2` (NodePort 30084). Бэкенды — отдельные Deployment+Service (по 1 поду `hashicorp/http-echo` каждый) в namespace `benchmark`. Разделение нужно, чтобы нагрузка двух прокси не суммировалась на одном поде, а в метриках upstream (`nginx_upstream_*`, `angie_http_upstreams_peers_*`) было видно 2 peer'а.

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
| Базовый сервер | Голый **nginx 1.31.3** (mainline) из исходников (`nginx.org/download/nginx-1.31.3.tar.gz`), базовый образ `nginx:1.31.3-trixie` (Debian 13 trixie, PCRE2) |
| Модуль метрик | **Сторонний** `nginx-module-vts` v0.2.6 — собирается как dynamic-модуль (`--add-dynamic-module`) и подключается через `load_module` |
| Экспорт в Prometheus | **Внешний sidecar-экспортёр** `nginx-vts-exporter` v0.10.8 (отдельный Go-бинарник, слушает `:9913`), парсит JSON-статус с `http://127.0.0.1:80/status` |
| Поставка | **Docker Compose** — nginx собирается из Dockerfile, рядом контейнер vector; всё изолированно, но образ нужно собирать (`docker compose up -d --build`) |
| Endpoint статуса | `/status` — JSON (формат VTS) |
| Web-консоль | **Нет** — только JSON `/status` и текстовый `/stub_status` |
| Количество метрик | ~12 метрик `nginx_*` (server, upstream, cache) |
| Зависимости | Docker, git, build-essential, libpcre2-dev, zlib1g-dev, libssl-dev — для сборки модуля на VM |
| Обновление | Пересборка Docker-образа при выходе новой версии nginx/VTS-модуля |

> Ключевой недостаток — сторонний модуль VTS нужно собирать под каждую версию nginx, а экспортёр — отдельный процесс, который может упасть независимо от nginx. VTS v0.2.6 (июль 2026) [возобновил поддержку](https://github.com/vozlt/nginx-module-vts/releases/tag/v0.2.6): правки безопасности (buffer overflow, XSS), совместимость с nginx 1.30+, React-фронтенд статусной страницы.

### angie

| Feature | Реализация |
|---|---|
| Базовый сервер | **Angie** — форк nginx от «Веб-Сервера», устанавливается deb-пакетом из репозитория `download.angie.software` |
| Модуль метрик | **Нативный** `http_prometheus` — входит в поставку Angie, подключается одной строкой `include /etc/angie/prometheus_all.conf` |
| Экспорт в Prometheus | **Без отдельного экспортёра** — метрики отдаёт сам Angie на `:80/metrics` (`prometheus all;`), отдельный процесс не нужен |
| Поставка | **deb-пакет** (`apt-get install angie`) — без Docker, без сборки, без управления зависимостями компилятора |
| Endpoint статуса | `/api/` — REST API (`api /status/`, JSON-дерево `/status/connections/`, `/status/http/server_zones/`, `/status/http/upstreams/` и т.д.), `/metrics` — Prometheus, `/status.html` — `stub_status` |
| Web-консоль | **[Console Light](https://angie.software/angie/docs/configuration/monitoring/)** — отдельный пакет `angie-console-light`, ставится через `apt-get install angie-console-light`, отдаётся на `/console/` через `alias /usr/share/angie-console-light/html/`. В реальном времени показывает connections, server zones, upstreams, caches, SSL; в бенчмарке устанавливается в `cloud-init/angie.yaml` (доступна по `http://angie-console.<angie_ip>.sslip.io/console/`, URL выводится в `terraform output angie_console_url`) |
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
| `benchmark-k8s.tf` | Namespace "benchmark", 4 бэкенда (2 для vts, 2 для angie), ConfigMap с k6-скриптом |
| `benchmark-runners.tf` | k6 Job для каждого варианта |
| `values/victoriametrics-values.yaml` | Helm values: VictoriaMetrics + Grafana + vmagent (генерируется) |
| `values/victoria-logs-cluster-values.yaml` | Helm values: VictoriaLogs cluster + vlinsert ingress (генерируется) |
| `values/victoria-logs-collector-values.yaml` | Helm values: лог-коллектор |
| `values/*.tftpl` | Шаблоны values (рендерятся Terraform через `templatefile`) |
| `benchmark/templates/backend.yaml.tftpl` | Шаблон бэкенда (Deployment+Service, NodePort) — рендерится 4 раза: backend-vts-1/2, backend-angie-1/2 |
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
  --version 0.88.0 \
  --namespace vmks --create-namespace \
  -f ./values/victoriametrics-values.yaml

# Версия victoria-metrics-k8s-stack 0.88.0 содержит исправление бага config-reloader'а
# VMAgent на Kubernetes 1.33 (issue https://github.com/VictoriaMetrics/helm-charts/issues/3136):
# ранее config-reloader не перечитывал Secret с конфигом скрейпов при пересоздании VM / смене IP,
# и без kubectl rollout restart deployment vmagent-vm-stack -n vmks скрейпы шли на устаревшие
# адреса. Начиная с 0.88.0 workaround не требуется.

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

После установки `vmks` примените ConfigMap с Grafana-дашбордом (namespace `vmks` уже создан Helm'ом выше, файл сгенерирован Terraform):

```bash
kubectl apply -f benchmark/manifests/benchmark-dashboard-configmap.yaml
```

### 4. Применение benchmark-манифестов

Terraform рендерит 4 отдельных backend-манифеста (по одному на backend: `backend-vts-1/2.yaml`, `backend-angie-1/2.yaml`) из шаблона `benchmark/templates/backend.yaml.tftpl` — каждый содержит и Deployment, и Service. Команда также выводится в `terraform output kubectl_apply_benchmark_command`:

```bash
# Namespace, 4 backend'а (Deployment+Service, NodePort), ConfigMap'ы с k6-скриптом и env
kubectl apply -f benchmark/manifests/namespace.yaml
kubectl apply -f benchmark/manifests/backend-vts-1.yaml -f benchmark/manifests/backend-vts-2.yaml \
  -f benchmark/manifests/backend-angie-1.yaml -f benchmark/manifests/backend-angie-2.yaml \
  -f benchmark/manifests/k6-script-configmap.yaml -f benchmark/manifests/k6-env-configmap.yaml
```

### 5. Запуск бенчмарка

Бенчмарк состоит из **3 разделов** (Low / Medium / High — см. «Ключевые результаты»). Каждый раздел запускается отдельно: сначала меняются ресурсы VM через Terraform, дожидаются cloud-init, проверяются сервисы, затем запускаются k6 jobs. Результаты каждого раздела заносятся в таблицу «Ключевые результаты».

#### Подготовка раздела (общая процедура для каждого из 3 разделов)

1. Задать ресурсы VM в `benchmark-vms.tf` согласно таблице раздела (Low: 2 c / 4 ГБ; Medium: 4 c / 8 ГБ; High: 4 c / 8 ГБ). Сеть `software_accelerated` во всех разделах — не меняется.
2. Задать `MAX_VUS` (100 / 200 / 300) в `benchmark/templates/k6-job.yaml.tftpl` (env `MAX_VUS`).
3. Применить изменения и дождаться поднятия сервисов:

```bash
# Обновить ресурсы VM (Terraform остановит/запустит VM — см. AGENTS.md про потерю NAT IP)
terraform apply -auto-approve

# Если сменился публичный IP VM (ephemeral NAT): taint + re-apply (см. AGENTS.md)
# Затем обновить k6-env ConfigMap и vmagent scrape config с новыми IP:
kubectl apply -f ./benchmark/manifests/k6-env-configmap.yaml
helm upgrade vmks victoriametrics/victoria-metrics-k8s-stack --version 0.88.0 --namespace vmks \
  -f ./values/victoriametrics-values.yaml
kubectl rollout restart deployment vmagent-vm-stack -n vmks 2>/dev/null || true

# Дождаться завершения cloud-init на VM (особенно nginx-vts-docker: docker build ~2-3 мин)
# Проверить health сервисов на VM — все должны ответить 200 (HTTP / может быть 404, т.к. root location не настроен):
for name_ip in "nginx-vts-docker:$(terraform output -raw vm_nginx_vts_docker_ip)" "angie:$(terraform output -raw vm_angie_ip)"; do
  name="${name_ip%%:*}"; ip="${name_ip##*:}"
  echo "=== $name ($ip) ==="
  echo -n "  HTTP: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/"
  echo -n "  Vector: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9598/metrics"
  case "$name" in
    nginx-vts-docker)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9913/metrics"
      echo -n "  Status: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/status"
      ;;
    angie)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/metrics"
      echo -n "  API: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/api/"
      ;;
  esac
done
```

#### Запуск k6 jobs для раздела

```bash
# Оба варианта параллельно (nginx-vts-docker + angie)
kubectl delete job k6-nginx-vts-docker k6-angie -n benchmark --ignore-not-found
kubectl apply -f benchmark/manifests/k6-nginx-vts-docker-job.yaml -f benchmark/manifests/k6-angie-job.yaml
```

Дождаться завершения (~8м30с на раздел) и собрать результаты (см. шаг 6). Повторить процедуру для каждого из 3 разделов, после чего заполнить таблицу «Ключевые результаты».

> **Важно:** ресурсы VM nginx-vts-docker и angie должны быть **одинаковыми** в рамках одного раздела — иначе сравниваются не прокси, а железо. Между разделами ресурсы меняются ступенчато (2c/4GB → 4c/8GB), чтобы показать, как прокси масштабируются при росте ресурсов и нагрузки.

### 6. Проверка результатов

```bash
# Статус k6 jobs
kubectl get jobs -n benchmark
kubectl get pods -n benchmark -l app=k6

# Логи k6 (итоговая сводка в конце)
kubectl logs job/k6-nginx-vts-docker -n benchmark
kubectl logs job/k6-angie -n benchmark

# Проверка сервисов на VM
# У каждого прокси свой порт метрик: nginx-vts-docker отдаёт :9913/metrics (nginx-vts-exporter),
# angie — :80/metrics (нативный Prometheus). Поэтому endpoint метрик выбирается по имени варианта,
# а не через конструкцию `curl ... || curl ...` (она склеивает выводы обоих curl в строку вида "000200").
for name_ip in "nginx-vts-docker:$(terraform output -raw vm_nginx_vts_docker_ip)" "angie:$(terraform output -raw vm_angie_ip)"; do
  name="${name_ip%%:*}"; ip="${name_ip##*:}"
  echo "=== $name ($ip) ==="
  echo -n "  HTTP: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/" || echo "FAIL"
  echo -n "  Vector: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9598/metrics" || echo "N/A"
  case "$name" in
    nginx-vts-docker)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9913/metrics" || echo "FAIL"
      echo -n "  Status: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/status" || echo "FAIL"
      ;;
    angie)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/metrics" || echo "FAIL"
      echo -n "  API: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/api/" || echo "FAIL"
      ;;
  esac
done

# Web-консоль Angie (Console Light) — открывается в браузере
# (после terraform apply с обновлённым cloud-init; HTTP 200 + HTML отдаёт Console Light,
#  а не backend — последний отвечает "OK" на любой путь через location /)
ANGIE_IP=$(terraform output -raw vm_angie_ip)
curl -s -m 10 -o /dev/null -w "Angie Console Light: HTTP %{http_code}\n" "http://angie-console.$ANGIE_IP.sslip.io/console/"
echo "Открыть в браузере: http://angie-console.$ANGIE_IP.sslip.io/console/"

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

### Готовый дашборд в Grafana

Дашборд **«Nginx-VTS vs Angie Benchmark»** (33 панели + 1 row-разделитель) применяется в Grafana через ConfigMap `benchmark-dashboard` (namespace `vmks`, лейбл `grafana_dashboard: "1"`, файл `benchmark/manifests/benchmark-dashboard-configmap.yaml`), который подхватывает sidecar `grafana-sc-dashboard` чарта `vmks`. Файл манифеста генерируется Terraform из шаблона `benchmark/templates/benchmark-dashboard-configmap.yaml.tftpl`; команда применения выводится в `terraform output kubectl_apply_dashboard_command` и продублирована на шаге 3. Ручной импорт через JSON не требуется.

Дашборд разбит на две секции:

1. **Сравнение (3 сводные панели)** — RPS по вариантам, входящий трафик (Bytes Received), исходящий трафик (Bytes Sent). Парные запросы nginx-vts и angie на одной панели для сопоставления.
2. **Парные метрики nginx-vts (слева) vs angie (справа) (1 row + 30 парных панелей = 15 пар)** — один общий row, в котором похожие метрики размещены рядом: nginx-vts всегда в левой колонке (`x: 0`), angie — в правой (`x: 12`), пары идут друг за другом по вертикали по темам: Connection states → Accepted/Handled → Server zone requests → HTTP responses by code → Server requestMsec → Cache status → Upstream responses by code → Upstream bytes → Upstream time/peer state → Shared zones/keepalive → Upstream health/selected → Slabs. Метрики без аналога (cache, upstream requestMsec — у nginx-vts; upstream keepalive/peer state/health/selected, slabs — у angie) помещены в тот же тематический row на свободной позиции с заголовком «(нет аналога …)» и пустым списком targets — для визуального параллелизма.

Дашборд использует метрики, которые scrape'ит vmagent (см. `values/victoriametrics-values.yaml.tftpl`, секция `extraObjects` → `vmks-additional-scrape-configs`):

- **nginx-vts-docker** (12 метрик `nginx_*`): `nginx_server_requests`, `nginx_server_bytes`, `nginx_server_connections`, `nginx_server_cache`, `nginx_server_requestMsec`, `nginx_server_sharedzones`, `nginx_upstream_bytes`, `nginx_upstream_requestMsec`, `nginx_upstream_requests`, `nginx_upstream_responseMsec`, `nginx_server_info`, `nginx_vts_exporter_build_info` — через `nginx-vts-exporter` на `:9913/metrics`.
- **angie** (26 метрик `angie_*`): `angie_connections_*` (4), `angie_http_server_zones_*` (6), `angie_http_upstreams_keepalive`, `angie_http_upstreams_peers_*` (8), `angie_slabs_*` (7) — нативный Prometheus на `:80/metrics`.

Datasource в Grafana — `VictoriaMetrics` (type `prometheus`, url `http://vmsingle-vm-stack.vmks.svc.cluster.local.:8428`), создаётся чартом автоматически. Откройте дашборд: Grafana → Dashboards → **Nginx-VTS vs Angie Benchmark** (папка `default`), либо напрямую по UID `nginx-vts-vs-angie-benchmark`:

```bash
echo "http://$(terraform output -raw grafana_url | sed 's|http://||')/d/nginx-vts-vs-angie-benchmark"
```

### Angie Console Light

Web-консоль Angie (визуальный мониторинг в реальном времени: connections, server zones, upstreams, caches, SSL) доступна по адресу, который выводится в `terraform output`:

```bash
terraform output angie_console_url
# http://angie-console.<angie_ip>.sslip.io/console/
```

Откройте URL в браузере (без аутентификации — `auth_basic` намеренно не включён, т.к. IP VM публичный только на время замера; для production добавьте `auth_basic`).

> sslip.io — бесплатный wildcard-DNS: `<anything>.<IP>.sslip.io` всегда резолвится в `<IP>`. Не требует делегирования доменной зоны.

## Метрики Angie «из коробки»

Angie собран с модулем `http_prometheus`. Для публикации метрик в конфиг добавлено:

```nginx
http {
    include /etc/angie/prometheus_all.conf;   # готовый шаблон "all"

    upstream backend {
        zone upstream_backend 64k;             # обязательно для сбора статистики upstream
        server <node_ip>:30083;                 # backend-angie-1 (NodePort)
        server <node_ip>:30084;                 # backend-angie-2 (NodePort)
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

Консоль доступна в браузере по `http://angie-console.<angie_ip>.sslip.io/console/` (URL выводится в `terraform output angie_console_url`; домен формируется через sslip.io из публичного IP VM Angie, `server_name _;` в конфиге принимает любой Host). Без аутентификации — в этом бенчмарке `auth_basic` намеренно не включён, т.к. IP VM публичный только на время замера; для production добавьте `auth_basic`. У nginx-vts аналога нет — только JSON `/status`.

## Особенности доставки логов (vector → VictoriaLogs)

В cloud-init vector отправляет логи в vlinsert по HTTP. Два важных момента, найденных при отладке:

1. **`framing.method = "newline_delimited"`** — без него vector сериализует батч как JSON-**массив** (`[{...},{...}]`), а VictoriaLogs `/insert/jsonline` ожидает **по одному объекту на строку**. Иначе — `400 Bad Request` с ошибкой `value doesn't contain object; it contains array`.
2. **Корректный query-string** — параметры разделяются `&`, а не запятой: `?_stream_fields=instance&_msg_field=msg&_time_field=ts`.
3. **`batch.max_bytes`** — ограничение размера батча (~900KB) предотвращает `413 Payload Too Large` при всплеске логов под нагрузкой.

Remap-трансформы добавляют поле `instance` (stream label) и человекочитаемый `msg` (`METHOD URI STATUS`), поэтому в VictoriaLogs логи удобно фильтровать по `_stream:{instance="angie"}`.

## Особенность сборки nginx-vts-docker (Docker Hub mirror + fallback apt-зеркала)

cloud-init VM `nginx-vts-docker` собирает образ `nginx:1.31.3-trixie` и тянет `timberio/vector:0.57.0-debian` с Docker Hub. Иногда `production.cloudfront.docker.com` (CDN Docker Hub) отдаёт `i/o timeout` из сети Yandex Cloud — cloud-init падает на `docker compose up`, и сервисы на VM не поднимаются. Чтобы этого избежать, в `benchmark/cloud-init/nginx-vts-docker.yaml`:

1. **`/etc/docker/daemon.json`** с `"registry-mirrors": ["https://mirror.gcr.io"]` — Docker тянет образы через публичный mirror `mirror.gcr.io` (Google), который стабильно доступен из Yandex Cloud и кэширует Docker Hub.
2. **Retry `docker pull`** для `timberio/vector:0.57.0-debian` и `nginx:1.31.3-trixie` (5 попыток с паузой 10с) + повторный `docker compose up --build`, если первый запуск не поднял контейнер `nginx-vts`.
3. **Fallback apt-репозитория Docker** — `runcmd` сначала пробует зеркало `mirror.yandex.ru/mirrors/download.docker.com` (быстрее из сети Yandex Cloud), а если `apt-get install docker-ce` падает (яндексовское зеркало периодически рассинхронизируется: размер `Packages.bz2` не совпадает, `Package 'docker-ce' has no installation candidate`), переключается на прямой `download.docker.com` и повторяет установку. Без этого fallback cloud-init завершается с `status: error`, docker не установлен, сервисы не поднимаются.

Проверено из VM Yandex Cloud: `mirror.gcr.io/v2/timberio/vector/manifests/0.57.0-debian` → `HTTP 200` (тогда как прямой `registry-1.docker.io` периодически таймаутит). Прямой `download.docker.com/linux/ubuntu/dists/jammy/stable/binary-amd64/Packages.bz2` → `HTTP 200` с корректным размером (тогда как `mirror.yandex.ru` в моменты синхронизации отдаёт неверный размер).

## Конфигурация ресурсов и сети VM/K8s

Бенчмарк состоит из **3 разделов** с разными ресурсами VM и сетью (см. «Ключевые результаты»). Конкретная конфигурация для каждого раздела задаётся в `benchmark-vms.tf` (`resources`, `network_acceleration_type`) и применяется через `terraform apply` перед прогоном раздела. Ресурсы VM nginx-vts-docker и angie **всегда одинаковые** в рамках одного раздела — чтобы сравнивать прокси, а не железо.

Сводка по всем разделам:

| Раздел | K8s node group | VM nginx-vts-docker | VM angie | Сеть VM |
|---|---|---|---|---|
| **Low**    | 4 c / 8 ГБ, preemptible | 2 c / 4 ГБ, preemptible | 2 c / 4 ГБ, preemptible | software-accelerated |
| **Medium** | 4 c / 8 ГБ, preemptible | 4 c / 8 ГБ, preemptible | 4 c / 8 ГБ, preemptible | software-accelerated |
| **High**   | 4 c / 8 ГБ, preemptible | 4 c / 8 ГБ, preemptible | 4 c / 8 ГБ, preemptible | software-accelerated |

Все инстансы — платформа `standard-v2`, **preemptible** (`scheduling_policy.preemptible = true`), сеть **software-accelerated** (`network_acceleration_type = "software_accelerated"`). K8s node group во всех разделах: 4 c / 8 ГБ (не меняется, т.к. нагрузка от k6 идёт через K8s).

`software_accelerated` — ускоренная сеть Yandex Cloud (без GPU, доступно на `standard-v2`): снижает overhead на сетевом I/O. Включается в `k8s.tf` (`instance_template.network_acceleration_type`) и `benchmark-vms.tf` (верхнеуровневое поле `network_acceleration_type` ресурса `yandex_compute_instance`).

> ⚠️ При изменении ресурсов/ускоренной сети Terraform останавливает VM (`allow_stopping_for_update = true`), а Yandex Compute **освобождает ephemeral NAT IP** на stop — после stop/start SSH/HTTP по старому публичному IP перестают отвечать. Процедура восстановления (taint VM → re-apply → обновить k6-env ConfigMap → helm upgrade vmks → restart vmagent) описана в `AGENTS.md`.

## k6 сценарий нагрузки

k6-скрипт (`benchmark/k6/benchmark.js`) параметризован через env-переменную `MAX_VUS` (пиковое значение VU). Один и тот же сценарий для всех 3 разделов — меняется только `MAX_VUS` (100 / 200 / 300):

1. **Warmup**: 10 VU × 30 сек
2. **Ramp-up**: 0 → 50 VU за 30 сек
3. **Sustained**: 50 VU × 120 сек
4. **Peak ramp**: 50 → `MAX_VUS` × 0.5 за 30 сек
5. **Peak sustained (mid)**: `MAX_VUS` × 0.5 × 120 сек
6. **High peak ramp**: `MAX_VUS` × 0.5 → `MAX_VUS` за 30 сек
7. **High peak sustained**: `MAX_VUS` × 120 сек
8. **Cooldown**: `MAX_VUS` → 0 за 30 сек

При `MAX_VUS=300` промежуточная ступень = 150 (ранее была 100, но логика та же — ramp через половину пика). Значение `MAX_VUS` передаётся в k6 job через env (см. `benchmark/templates/k6-job.yaml.tftpl`), по умолчанию 300. Общая длительность — 8м30с (30с warmup + 8м load).

> **Требования к памяти k6:** при `MAX_VUS=300` k6 потребляет до ~1 ГБ RAM. Шаблон `k6-job.yaml.tftpl` задаёт лимит 2Gi. При уменьшении лимита до 512Mi k6 падает с `OOMKilled` после ~8 минут работы (см. `ERRORS.md`).

## Соответствие метрик nginx-vts и angie

Таблица маппинга похожих метрик nginx-vts-docker (`nginx_*`, 12 метрик через `nginx-vts-exporter` на `:9913/metrics`) и angie (`angie_*`, 26 метрик через нативный Prometheus на `:80/metrics`). Метрики сгруппированы по темам; в каждой строке слева — метрика nginx-vts, справа — похожая метрика angie. Строки, где аналог отсутствует, помечены «—» в соответствующей колонке. Эта таблица — источник парных панелей в дашборде Grafana (см. «Готовый дашборд в Grafana»).

### Connections

| Тема | nginx-vts (метрика, лейблы) | angie (метрика, лейблы) | Тип | Примечание |
|---|---|---|---|---|
| Active connections | `nginx_server_connections{status="active"}` | `angie_connections_active` | gauge | текущие активные соединения |
| Reading | `nginx_server_connections{status="reading"}` | — | gauge | Angie не разделяет неактивные соединения по состояниям |
| Writing | `nginx_server_connections{status="writing"}` | — | gauge | то же |
| Waiting | `nginx_server_connections{status="waiting"}` | — | gauge | то же |
| Idle connections | — | `angie_connections_idle` | gauge | суммарные простаивающие; у nginx-vts аналога нет (раскладывается на reading/writing/waiting) |
| Accepted connections | `nginx_server_connections{status="accepted"}` (rate) | `angie_connections_accepted` (rate) | counter | принято соединений |
| Handled connections | `nginx_server_connections{status="handled"}` (rate) | — | counter | Angie не экспортирует handled отдельно (handled = accepted при drop=0) |
| Dropped connections | — | `angie_connections_dropped` (rate) | counter | сброшенные соединения; nginx-vts не экспортирует dropped (можно вычислить как accepted − handled) |
| Total requests (connection-level) | `nginx_server_connections{status="requests"}` (rate) | — | counter | суммарные запросы на уровне соединений; у angie учитывается в server_zones (`angie_http_server_zones_requests_total`) |

### Server zone / HTTP

| Тема | nginx-vts (метрика, лейблы) | angie (метрика, лейблы) | Тип | Примечание |
|---|---|---|---|---|
| Server zone requests total | `nginx_server_requests{code="total"}` (rate) | `angie_http_server_zones_requests_total` (rate) | counter | суммарные запросы в server zone |
| Requests processing | — | `angie_http_server_zones_requests_processing` | gauge | запросы в обработке; nginx-vts аналога не имеет |
| Requests discarded | — | `angie_http_server_zones_requests_discarded` (rate) | counter | отброшенные запросы; nginx-vts аналога не имеет |
| HTTP responses by code | `nginx_server_requests{code!~"total"}` (rate by `code`) | `angie_http_server_zones_responses` (rate by `code`) | counter | 1xx/2xx/3xx/4xx/5xx |
| Bytes received (in) | `nginx_server_bytes{direction="in"}` (rate) | `angie_http_server_zones_data_received` (rate) | counter | входящий трафик server zone |
| Bytes sent (out) | `nginx_server_bytes{direction="out"}` (rate) | `angie_http_server_zones_data_sent` (rate) | counter | исходящий трафик server zone |
| Server request processing time | `nginx_server_requestMsec` (avg) | — | gauge (avg) | среднее время обработки запроса, мс; angie не экспортирует per-request processing time в server zone |
| Cache status | `nginx_server_cache` (rate by `status`) | — | counter | hit/miss/bypass/expired/revalidated/scarce/stale/updating; в бенчмарке angie не настроен с кэшем |

### Upstream

| Тема | nginx-vts (метрика, лейблы) | angie (метрика, лейблы) | Тип | Примечание |
|---|---|---|---|---|
| Upstream responses by code | `nginx_upstream_requests` (rate by `code`) | `angie_http_upstreams_peers_responses` (rate by `code`) | counter | ответы upstream по кодам |
| Upstream bytes in | `nginx_upstream_bytes{direction="in"}` (rate) | `angie_http_upstreams_peers_data_received` (rate) | counter | байты от upstream (in) |
| Upstream bytes out | `nginx_upstream_bytes{direction="out"}` (rate) | `angie_http_upstreams_peers_data_sent` (rate) | counter | байты к upstream (out) |
| Upstream request time | `nginx_upstream_requestMsec` (avg) | — | gauge (avg) | время запроса к upstream, мс; angie аналога не имеет |
| Upstream response time | `nginx_upstream_responseMsec` (avg) | — | gauge (avg) | время ответа от upstream, мс; angie аналога не имеет |
| Upstream keepalive | — | `angie_http_upstreams_keepalive` | gauge | текущие keepalive-соединения к upstream; nginx-vts не экспортирует |
| Upstream peer state | — | `angie_http_upstreams_peers_state` (by `peer`) | gauge | состояние peer'а (0=up); nginx-vts не экспортирует |
| Upstream peer health: fails | — | `angie_http_upstreams_peers_health_fails` (rate) | counter | неудачи peer'а; nginx-vts не экспортирует |
| Upstream peer health: unavailable | — | `angie_http_upstreams_peers_health_unavailable` (rate) | counter | недоступность peer'а; nginx-vts не экспортирует |
| Upstream peer health: downtime | — | `angie_http_upstreams_peers_health_downtime` | gauge | суммарное время простоя peer'а, с; nginx-vts не экспортирует |
| Upstream peer selected: current | — | `angie_http_upstreams_peers_selected_current` | gauge | текущие выбранные peer'ы; nginx-vts не экспортирует |
| Upstream peer selected: total | — | `angie_http_upstreams_peers_selected_total` (rate) | counter | всего выбраний peer'а; nginx-vts не экспортирует |

### Shared memory / Slabs

| Тема | nginx-vts (метрика, лейблы) | angie (метрика, лейблы) | Тип | Примечание |
|---|---|---|---|---|
| Shared zone usedsize | `nginx_server_sharedzones{memstat="usedsize"}` | — | gauge | занято в зоне `ngx_http_vhost_traffic_status`; angie не экспортирует usedsize для этой зоны |
| Shared zone maxsize | `nginx_server_sharedzones{memstat="maxsize"}` | — | gauge | лимит зоны `ngx_http_vhost_traffic_status`; angie не экспортирует maxsize для этой зоны |
| Slabs pages free | — | `angie_slabs_pages_free` | gauge | свободные страницы slab-зоны `upstream_backend`; nginx-vts не экспортирует slabs |
| Slabs pages used | — | `angie_slabs_pages_used` | gauge | занятые страницы slab-зоны; nginx-vts не экспортирует |
| Slabs slots used | — | `angie_slabs_pages_slots_used` (by `size`) | gauge | занятые слоты по размеру; nginx-vts не экспортирует |
| Slabs slots free | — | `angie_slabs_pages_slots_free` (by `size`) | gauge | свободные слоты по размеру; nginx-vts не экспортирует |
| Slabs slots reqs | — | `angie_slabs_pages_slots_reqs` (rate by `size`) | counter | запросы выделения слотов; nginx-vts не экспортирует |
| Slabs slots fails | — | `angie_slabs_pages_slots_fails` (rate by `size`) | counter | неудачи выделения слотов; nginx-vts не экспортирует |

### Прочие метрики без пары

| Метрика | Источник | Тип | Примечание |
|---|---|---|---|
| `nginx_server_info` | nginx-vts | info | метаданные сервера (`Info`-тип, значение 1) |
| `nginx_vts_exporter_build_info` | nginx-vts-exporter | info | версия экспортёра (`Info`-тип, значение 1) |

## Очистка

```bash
terraform destroy
```
