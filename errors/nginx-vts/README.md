# Ошибка: nginx-vts (native VM) — nginx не стартует, vector в restart-цикле

## Симптомы

```bash
$ ssh ubuntu@<vm_ip> "sudo docker ps"
CONTAINER ID   IMAGE                           COMMAND                  STATUS                          NAMES
a3f62c2be2e7   timberio/vector:0.57.0-debian   "/usr/bin/vector"        Restarting (78) 54 seconds ago  vector
c90efa19d853   nginx-vts-nginx-vts             "/docker-entrypoint.…"   Restarting (1) 54 seconds ago   nginx-vts
```

k6-бенчмарк завершается с ошибкой: 100% запросов `connection refused`, job `Failed` (threshold `errors` crossed).

> Примечание: несмотря на название «native», cloud-init этой VM также использует docker-compose (`/opt/nginx-vts/docker-compose.yml`) — конфигурация идентична nginx-vts-docker, только каталог `/opt/nginx-vts`.

## Ошибка 1: nginx — `unexpected "}" in /etc/nginx/nginx.conf:31`

```bash
$ ssh ubuntu@<vm_ip> "sudo docker logs nginx-vts --tail 5"
nginx: [emerg] unexpected "}" in /etc/nginx/nginx.conf:31
```

### Причина

В `benchmark/cloud-init/nginx-vts.yaml` (строки 29–45) директива `log_format ... escape=json` записана **многострочной конкатенацией строк** в одинарных кавычках. Парсер nginx в этой конфигурации не воспринимает переносы строк внутри log_format и падает с `[emerg] unexpected "}"`.

Проблемный фрагмент (текущий `nginx-vts.yaml`):

```nginx
log_format json_combined escape=json
    '{'
        '"ts":"$time_iso8601",'
        ...
        '"bytes_sent":$bytes_sent
    '}';
```

### Исправление

Записать весь log_format **одной строкой**:

```nginx
log_format json_combined escape=json '{"ts":"$time_iso8601","remote_addr":"$remote_addr","request_method":"$request_method","request_uri":"$request_uri","status":$status,"body_bytes_sent":$body_bytes_sent,"request_time":$request_time,"upstream_response_time":"$upstream_response_time","upstream_addr":"$upstream_addr","http_user_agent":"$http_user_agent","http_host":"$http_host","server_protocol":"$server_protocol","request_length":$request_length,"bytes_sent":$bytes_sent}';
```

### Воспроизведение / проверка (ручной фикс на живой VM)

```bash
ssh ubuntu@<vm_ip>
sudo python3 - <<'EOF'
content = open("/opt/nginx-vts/nginx.conf").read()
start = content.find("    log_format json_combined escape=json")
end = content.find("'}';", start) + 5
new = "    log_format json_combined escape=json '{\"ts\":\"$time_iso8601\",\"remote_addr\":\"$remote_addr\",\"request_method\":\"$request_method\",\"request_uri\":\"$request_uri\",\"status\":$status,\"body_bytes_sent\":$body_bytes_sent,\"request_time\":$request_time,\"upstream_response_time\":\"$upstream_response_time\",\"upstream_addr\":\"$upstream_addr\",\"http_user_agent\":\"$http_user_agent\",\"http_host\":\"$http_host\",\"server_protocol\":\"$server_protocol\",\"request_length\":$request_length,\"bytes_sent\":$bytes_sent}';"
open("/opt/nginx-vts/nginx.conf", "w").write(content[:start] + new + content[end:])
EOF
sudo docker run --rm --entrypoint nginx -v /opt/nginx-vts/nginx.conf:/etc/nginx/nginx.conf:ro nginx-vts-nginx-vts -t
# ожидаем: syntax is ok / test is successful
sudo docker compose -f /opt/nginx-vts/docker-compose.yml up -d --force-recreate
curl -s -o /dev/null -w "%{http_code}\n" http://<vm_ip>:9913/metrics   # 200
```

## Ошибка 2: vector — exit code 78 (CONFIG)

```bash
$ ssh ubuntu@<vm_ip> "sudo docker logs vector --tail 5"
ERROR vector::topology::builder: Configuration error. error=Source "nginx_access": data_dir "/var/lib/vector" does not exist
ERROR ... error[E652]: only objects can be merged ... Transform "parse_error"
```

### Причина 2а: data_dir не существует

В `vector.toml` указан `data_dir = "/var/lib/vector"`. Каталог существует только **внутри контейнера** vector (volume `vector-data`), но при первом запуске volume пуст — vector его создать не может при чтении конфига до старта topology.

### Причина 2б: невалидный VRL в transform `parse_error`

```toml
[transforms.parse_error]
source = '''
. |= parse_json(.message) ?? { "msg": .message }
'''
```

Оператор `.|=` (merge assignment) требует объект справа; выражение возвращает не-объект, когда строка error.log не является JSON. Правильный вариант:

```toml
[transforms.parse_error]
type = "remap"
inputs = ["nginx_error"]
source = '''
if is_json(string!(.message)) {
    parsed, err = parse_json(.message)
    if err == null && is_object(parsed) { . = merge!(., parsed) } else { .msg = .message }
} else {
    .msg = .message
}
'''
```

### Исправление (в cloud-init `nginx-vts.yaml`)

1. Добавить в `runcmd` **перед** `docker compose up`:

```yaml
runcmd:
  - mkdir -p /var/lib/vector
  # ... установка docker ...
  - docker compose -f /opt/nginx-vts/docker-compose.yml up -d
```

2. Заменить `[transforms.parse_error]` на вариант выше.

### Воспроизведение / проверка (ручной фикс)

```bash
ssh ubuntu@<vm_ip>
# правим /opt/nginx-vts/vector.toml (см. выше), затем:
sudo docker compose -f /opt/nginx-vts/docker-compose.yml restart vector
sudo docker logs vector --tail 5   # нет ERROR
curl -s -o /dev/null -w "%{http_code}\n" http://<vm_ip>:9598/metrics  # 200
```

## Файлы Terraform, относящиеся к этой ошибке

| Файл | Что делает |
|------|-----------|
| `errors/nginx-vts/benchmark-vms.tf` | VM `nginx-vts` (user-data → cloud-init с багом) |
| `errors/nginx-vts/net.tf` | Сеть/подсеть, к которой подключена VM |
| `errors/nginx-vts/variables.tf` | `backend_addr`, `vlinsert_addr` — подставляются в cloud-init |
| `errors/nginx-vts/versions.tf` | Провайдер `yandex-cloud/yandex` |
| `errors/nginx-vts/cloud-init/nginx-vts.yaml` | **Проблемный cloud-init** (точная копия из `benchmark/cloud-init/`) |

## Постоянное исправление в репозитории

1. `benchmark/cloud-init/nginx-vts.yaml`:
   - log_format → одна строка (см. выше)
   - `[transforms.parse_error]` → валидный VRL
   - `runcmd`: добавить `mkdir -p /var/lib/vector`
2. `terraform apply` — изменение `user-data` пересоздаст VM.
3. Перезапустить k6-job: `kubectl delete job k6-nginx-vts -n benchmark && kubectl apply -f benchmark/manifests/k6-nginx-vts-job.yaml`
