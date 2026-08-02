# Ошибка: cloud-init на VM nginx-vts-docker завершился с ошибкой

## Симптом
- VM `nginx-vts-docker` (93.77.190.244) не отвечает по HTTP (порт 80), SSH (22), metrics (9913), vector (9598).
- VM `angie` (93.77.178.50) работает полностью (HTTP 200, /metrics 200, /api/ 200, /console/ 200).

## Причина (из serial port output VM nginx-vts-docker)
cloud-init на шаге `runcmd` выполнил:
```
docker compose -f /opt/nginx-vts-docker/docker-compose.yml up -d
```
Docker не смог скачать образ `timberio/vector:0.57.0-debian` с Docker Hub:
```
[  207.896408] cloud-init[735]: failed to copy: httpReadSeeker: failed open: failed to do request:
  Get "https://production.cloudfront.docker.com/.../data?Expires=...":
  dial tcp 65.9.46.11:443: i/o timeout
[  207.908945] cloud-init[735]: cc_scripts_user.py[WARNING]: Failed to run module scripts_user
[  207.910833] cloud-init[735]: Running module scripts_user ... failed
[FAILED] Failed to start Cloud-init: Final Stage.
```
Docker Hub (production.cloudfront.docker.com, 65.9.46.11:443) недоступен/нестабилен из сети Yandex Cloud — i/o timeout.

## Также потенциально затронуто
- Сборка `nginx:1.28-bookworm` (FROM в Dockerfile) тоже тянет образ с Docker Hub — может падать по той же причине.

## Окружение
- VM preemptible, Ubuntu 22.04, Docker CE 29.7.1 из зеркала mirror.yandex.ru (apt — работает).
- cloud-init: `benchmark/cloud-init/nginx-vts-docker.yaml`, runcmd строка 210: `docker compose -f /opt/nginx-vts-docker/docker-compose.yml up -d`

## Идея исправления
Настроить Docker daemon registry mirror, доступный из Yandex Cloud, через `/etc/docker/daemon.json` перед `docker compose up`.
