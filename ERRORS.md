# Найденные ошибки при выполнении README.md

## Ошибка 1: vlcollector не может отправить логи в VictoriaLogs (DNS no such host)

### Симптомы
- VictoriaLogs возвращает пустой результат на любой logsql-запрос (`/select/logsql/query`).
- В логах vlcollector (`kubectl logs -n vlcollector ds/vlcollector-victoria-logs-collector`) постоянно повторяется:
  ```
  couldn't send a block with size ... to "1:secret-url":
    Post "http://victoria-logs-cluster-vlinsert.victoria-logs-cluster:9481/insert/native?version=v1":
    dial tcp4: lookup victoria-logs-cluster-vlinsert.victoria-logs-cluster on 10.96.128.2:53: no such host
  ```
- Метрики vlinsert `/insert/native` не растут (`vl_http_requests_total{path="/insert/native"} 0`).

### Причина
В шаблоне `values/victoria-logs-collector-values.yaml.tftpl` (и сгенерированном из него `values/victoria-logs-collector-values.yaml`) URL `remoteWrite` указывает на несуществующее DNS-имя:
```yaml
remoteWrite:
  - url: http://victoria-logs-cluster-vlinsert.victoria-logs-cluster:9481
```

Согласно команде установки из README (шаг 3):
```bash
helm upgrade --install vlcluster \
  victoriametrics/victoria-logs-cluster \
  --version 0.2.8 \
  --namespace vlcluster --create-namespace \
  -f ./values/victoria-logs-cluster-values.yaml
```
Helm-релиз называется `vlcluster` и ставится в namespace `vlcluster`. Чарт `victoria-logs-cluster` создаёт сервис vlinsert с именем `${release-name}-victoria-logs-cluster-vlinsert`, то есть фактически:
- Service: `vlcluster-victoria-logs-cluster-vlinsert`
- Namespace: `vlcluster`

Значит корректный FQDN — `vlcluster-victoria-logs-cluster-vlinsert.vlcluster.svc.cluster.local.:9481`,
а шаблон ссылается на `victoria-logs-cluster-vlinsert.victoria-logs-cluster` (другое имя релиза и namespace).

### Исправление
В `values/victoria-logs-collector-values.yaml.tftpl` заменить строку `url:` на:
```yaml
  - url: http://vlcluster-victoria-logs-cluster-vlinsert.vlcluster.svc.cluster.local.:9481
```

После правки шаблона нужно:
1. Перегенерировать `values/victoria-logs-collector-values.yaml` (`terraform apply` или вручную).
2. Обновить Helm-релиз vlcollector:
   ```bash
   helm upgrade --install vlcollector victoriametrics/victoria-logs-collector \
     --version 0.3.7 --namespace vlcollector \
     -f ./values/victoria-logs-collector-values.yaml
   ```
3. Перезапустить DaemonSet vlcollector, чтобы он сразу подхватил новый URL:
   ```bash
   kubectl rollout restart ds vlcollector-victoria-logs-collector -n vlcollector
   ```

### Проверка
```bash
# Логи vlcollector больше не содержат "no such host"
kubectl logs -n vlcollector ds/vlcollector-victoria-logs-collector --tail=50 | grep -i "no such host"

# Метрика insert/native должна расти
kubectl run curl-vli --rm -i --restart=Never --image=curlimages/curl:8.10.0 -- \
  curl -s -m 10 "http://vlcluster-victoria-logs-cluster-vlinsert.vlcluster.svc.cluster.local.:9481/metrics" | grep 'vl_http_requests_total{path="/insert/native"'

# K8s-логи подов видны через vlselect Ingress
curl -s "http://victorialogs.<LB_IP>.sslip.io/select/logsql/streams" -G --data-urlencode 'query={kubernetes.pod_namespace=~".*"}' --data-urlencode 'limit=5'
```

### Замечание
Эта ошибка влияет **только на логи подов Kubernetes**, собираемые vlcollector. Логи самих прокси (nginx/angie) с VM шлются vector'ом напрямую во vlinsert по публичному Ingress-адресу — они попадают под ошибку 2 (см. ниже).

---

## Ошибка 2: vector на VM nginx-vts-docker/angie шлёт логи на устаревший IP vlinsert (логи прокси не доходят)

### Симптомы
- В VictoriaLogs есть K8s-логи подов (от vlcollector), но **нет логов прокси** с VM:
  ```
  curl "http://victorialogs.<LB_IP>.sslip.io/select/logsql/streams?query={instance=\"angie\"}" → {"values":[]}
  curl "http://victorialogs.<LB_IP>.sslip.io/select/logsql/streams?query={instance=\"nginx-vts-docker\"}" → {"values":[]}
  ```
- Метрики vector на VM показывают, что sink `victorialogs_access` получил лишь 1-2 события из тысяч прочитанных source'ом:
  - `angie_access` (file source): 3442 events read
  - `parse_access` (remap transform): 1343 received, 8 sent
  - `victorialogs_access` (http sink): received_events_count_sum = 2
- При этом curl с VM к `http://vlinsert.89.169.132.222.sslip.io:80/...` уходит в никуда (IP не принадлежит кластеру).

> **Примечание:** первичная гипотеза о том, что `parse_json!` отбрасывает не-JSON логи, **не подтвердилась**. После перенастройки URL на актуальный LB IP логи пошли в полном объёме (766k+ для angie, 771k+ для nginx-vts за ~20 минут). Проверка `log_format` в `/etc/angie/angie.conf` и `/opt/nginx-vts-docker/nginx.conf` показала, что access.log на обеих VM пишется в JSON-формате (`log_format json_combined escape=json`), поэтому `parse_json!` отрабатывает корректно. Низкие счётчики `sent_events` до исправления URL были следствием HTTP-ошибок sink'а (запросы уходили на несуществующий host), а не transform'а.

### Причина
В `variables.tf` переменная `vlinsert_addr` имеет hardcoded default с устаревшим IP:
```hcl
variable "vlinsert_addr" {
  description = "VictoriaLogs vlinsert address (host:port)"
  type        = string
  default     = "vlinsert.89.169.132.222.sslip.io:80"
}
```
Этот IP `89.169.132.222` — leftover от предыдущего запуска (статический адрес `yandex_vpc_address.addr` пересоздаётся при каждом `terraform apply`, IP меняется). Terraform подставляет `var.vlinsert_addr` в `benchmark-vms.tf` → `templatefile(... benchmark/cloud-init/{angie,nginx-vts-docker}.yaml ...)` → в конфиг vector'а:
```toml
uri = "http://${vlinsert_addr}/insert/jsonline?_stream_fields=instance&_msg_field=msg&_time_field=ts"
```
Текущий LB IP кластера (после `terraform apply`) — `93.77.190.104` (см. `terraform output grafana_url`), а vector шлёт на `89.169.132.222`. Запросы уходят в пустоту, логи прокси не появляются в VictoriaLogs.

### Исправление
`vlinsert_addr` должен вычисляться из текущего публичного IP балансировщика (`yandex_vpc_address.addr.external_ipv4_address[0].address`), а не быть hardcoded. Заменить переменную на `local`:

1. Удалить переменную `vlinsert_addr` из `variables.tf`.
2. В `benchmark-vms.tf` (и везде, где используется `var.vlinsert_addr`) заменить на `local.vlinsert_addr`.
3. В `locals` блока Terraform (например в `k8s.tf` или `benchmark-vms.tf`) добавить:
   ```hcl
   vlinsert_addr = "vlinsert.${yandex_vpc_address.addr.external_ipv4_address[0].address}.sslip.io:80"
   ```

После правки:
```bash
terraform apply            # пересоздаст VM с корректным vlinsert_addr в cloud-init
# ИЛИ вручную перенастроить vector на запущенных VM через SSH:
ssh ubuntu@<vm_ip> 'sudo sed -i "s|vlinsert\.[0-9.]*\.sslip\.io:80|vlinsert.<LB_IP>.sslip.io:80|g" /etc/vector/vector.toml && sudo systemctl restart vector'
```

### Проверка
```bash
# На VM: счётчик sent_events_total sink'а victorialogs_access должен расти
curl -s "http://<vm_ip>:9598/metrics" | grep 'victorialogs_access' | grep sent_events_total

# В VictoriaLogs: поток {instance="angie"} / {instance="nginx-vts-docker"} должны появиться
curl -s "http://victorialogs.<LB_IP>.sslip.io/select/logsql/streams" -G \
  --data-urlencode 'query={instance="angie"}' --data-urlencode 'limit=5'
curl -s "http://victorialogs.<LB_IP>.sslip.io/select/logsql/streams" -G \
  --data-urlencode 'query={instance="nginx-vts-docker"}' --data-urlencode 'limit=5'
```
