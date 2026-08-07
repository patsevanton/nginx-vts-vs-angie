# AGENTS.md

Operational notes for working with this repo's infrastructure (Yandex Cloud + K8s + VMs).

## Потеря ephemeral NAT IP при stop/start VM

Все 6 VM (`nginx-vts-<section>`, `angie-<section>` для section=low/medium/high) используют **ephemeral** NAT IP (`network_interface.nat = true` без явного `nat_ip_address`). При любом изменении ресурсов/платформы/ускоренной сети Terraform останавливает VM (`allow_stopping_for_update = true` в `benchmark-vms.tf` — обязательно для in-place обновления), а Yandex Compute **освобождает ephemeral NAT IP** на stop и не привязывает его обратно на start. Симптом: VM `RUNNING` с внутренним IP, но `nat_ip_address: None`, SSH/HTTP по старому публичному IP не отвечают, `terraform output` всё ещё показывает устаревший адрес.

### Восстановление

```bash
# 1. taint-нуть нужные VM, чтобы Terraform пересоздал их с новым ephemeral NAT IP
#    (6 VM: yandex_compute_instance.benchmark_vm["nginx-vts-<section>"], ["angie-<section>"])
#    Пример для всех 6:
for vm in nginx-vts-low angie-low nginx-vts-medium angie-medium nginx-vts-high angie-high; do
  terraform taint 'yandex_compute_instance.benchmark_vm["'$vm'"]'
done
terraform apply -auto-approve
# новые IP появятся в terraform output vm_all_ips (и vm_nginx_vts_docker_ip/vm_angie_ip для high-раздела)

# 2. перегенерированные манифесты применить в K8s (k6-env ConfigMap с новыми target IP)
kubectl apply -f ./benchmark/manifests/k6-env-configmap.yaml

# 3. перегенерированный vmagent scrape config (values/victoriametrics-values.yaml) — helm upgrade vmks
helm upgrade vmks victoriametrics/victoria-metrics-k8s-stack --version 0.88.0 --namespace vmks \
  -f ./values/victoriametrics-values.yaml

# 4. рестарт vmagent (только для чартов <=0.87.0, где не закрыт issue #3136; на 0.88.0+ не требуется)
kubectl rollout restart deployment vmagent-vm-stack -n vmks 2>/dev/null || true
```

> Для production имеет смысл привязать статический IP (`yandex_vpc_address` + `nat_ip_address` в `network_interface`), чтобы переживать stop/start без смены адресов. В этом бенчмарке ephemeral IP допустим, т.к. IP используется только на время замера, а все зависимые ресурсы (k6-env ConfigMap, vmagent scrape targets) перегенерируются Terraform'ом и применяются одной командой.

## Баг vmagent config-reloader (#3136)

`victoria-metrics-k8s-stack 0.87.0` на K8s 1.33: VMAgent не перечитывает Secret со скрейп-конфигом при пересоздании VM/смене IP, скрейпы идут на устаревшие адреса. Upstream: https://github.com/VictoriaMetrics/helm-charts/issues/3136 (status: `closed`, исправлен в `victoria-metrics-k8s-stack 0.88.0`).

Workaround для чартов <=0.87.0: `kubectl rollout restart deployment vmagent-vm-stack -n vmks` после смены IP VM / `helm upgrade vmks`. На `0.88.0+` workaround не требуется — config-reloader корректно перечитывает Secret. Версия в README (шаг 3) и командах recovery выше уже обновлены до `0.88.0`.

## Команды проверки (после любых изменений инфраструктуры)

```bash
# K8s нода: статус, версия, ресурсы, сеть
yc managed-kubernetes cluster get-credentials --id $(terraform output -raw k8s_cluster_credentials_command | rg -o 'cat\w+') --external --force
kubectl get nodes
yc managed-kubernetes node-group get <node-group-id> | rg -i "accel|preempt|cores|memory|platform"

# VM сервисы (health-check всех 6 VM)
for name_ip in $(terraform output -json vm_all_ips | jq -r 'to_entries[] | "\(.key):\(.value)"'); do
  name="${name_ip%%:*}"; ip="${name_ip##*:}"
  variant="${name%%-*}"
  echo "=== $name ($ip) ==="
  echo -n "  HTTP: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/"
  echo -n "  Vector: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9598/metrics"
  case "$variant" in
    nginx-vts)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip:9913/metrics"
      echo -n "  Status: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/status"
      ;;
    angie)
      echo -n "  Metrics: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/metrics"
      echo -n "  API: "; curl -s -m 10 -o /dev/null -w "%{http_code}\n" "http://$ip/api/"
      ;;
  esac
done

# vmagent active targets (должны быть up с актуальными IP)
kubectl port-forward -n vmks deploy/vmagent-vm-stack 18429:8429 &
curl -s "http://localhost:18429/api/v1/targets" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('data',{}).get('activeTargets',[]):
    job=t.get('labels',{}).get('job','')
    if 'vector' in job or 'nginx-vts' in job or 'angie' in job:
        print(' ',t.get('health'),'|',t.get('scrapeUrl'),'|',job)
"
```
