.PHONY: help init apply destroy benchmark run-k6-nginx-vts-docker run-k6-nginx-vts run-k6-angie

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform init

apply: ## Apply Terraform (deploy all infrastructure)
	terraform apply

destroy: ## Destroy all infrastructure
	terraform destroy

plan: ## Show Terraform plan
	terraform plan

output-ips: ## Show VM and cluster IPs
	@echo "=== VM IPs ==="
	@terraform output -raw vm_nginx_vts_docker_ip 2>/dev/null && echo " (nginx-vts-docker)" || echo "nginx-vts-docker: not deployed"
	@terraform output -raw vm_nginx_vts_ip 2>/dev/null && echo " (nginx-vts)" || echo "nginx-vts: not deployed"
	@terraform output -raw vm_angie_ip 2>/dev/null && echo " (angie)" || echo "angie: not deployed"
	@echo "=== K8s ==="
	@terraform output -raw k8s_cluster_credentials_command 2>/dev/null || echo "K8s: not deployed"

benchmark: ## Run all 3 benchmarks sequentially
	$(MAKE) run-k6-nginx-vts-docker
	@echo "--- Waiting 30s between tests ---"
	@sleep 30
	$(MAKE) run-k6-nginx-vts
	@echo "--- Waiting 30s between tests ---"
	@sleep 30
	$(MAKE) run-k6-angie
	@echo "=== All benchmarks complete ==="

run-k6-nginx-vts-docker: ## Run k6 benchmark against nginx-vts-docker
	@echo "=== Running k6 benchmark: nginx-vts-docker ==="
	terraform output -raw k8s_cluster_credentials_command | sh > /dev/null 2>&1 || true
	kubectl delete job k6-nginx-vts-docker -n benchmark --ignore-not-found
	kubectl apply -f - <<'EOF'
	$(shell terraform output -json k6_jobs 2>/dev/null | jq -r '.["nginx-vts-docker"]' 2>/dev/null || echo "")
	EOF
	@echo "Started k6-nginx-vts-docker job"

run-k6-nginx-vts: ## Run k6 benchmark against nginx-vts
	@echo "=== Running k6 benchmark: nginx-vts ==="
	terraform output -raw k8s_cluster_credentials_command | sh > /dev/null 2>&1 || true
	kubectl delete job k6-nginx-vts -n benchmark --ignore-not-found
	kubectl apply -f - <<'EOF'
	$(shell terraform output -json k6_jobs 2>/dev/null | jq -r '.["nginx-vts"]' 2>/dev/null || echo "")
	EOF
	@echo "Started k6-nginx-vts job"

run-k6-angie: ## Run k6 benchmark against angie
	@echo "=== Running k6 benchmark: angie ==="
	terraform output -raw k8s_cluster_credentials_command | sh > /dev/null 2>&1 || true
	kubectl delete job k6-angie -n benchmark --ignore-not-found
	kubectl apply -f - <<'EOF'
	$(shell terraform output -json k6_jobs 2>/dev/null | jq -r '.["angie"]' 2>/dev/null || echo "")
	EOF
	@echo "Started k6-angie job"

benchmark-status: ## Check k6 job status
	@echo "=== k6 Jobs ==="
	kubectl get jobs -n benchmark 2>/dev/null || echo "Not connected to K8s"
	@echo ""
	@echo "=== k6 Pods ==="
	kubectl get pods -n benchmark -l app=k6 2>/dev/null || echo "Not connected to K8s"

benchmark-logs: ## Get k6 logs (last run)
	@for job in k6-nginx-vts-docker k6-nginx-vts k6-angie; do \
		echo "=== Logs: $$job ==="; \
		kubectl logs job/$$job -n benchmark 2>/dev/null || echo "No logs"; \
		echo ""; \
	done

vm-ssh-nginx-vts-docker: ## SSH into nginx-vts-docker VM
	ssh root@$$(terraform output -raw vm_nginx_vts_docker_ip)

vm-ssh-nginx-vts: ## SSH into nginx-vts VM
	ssh root@$$(terraform output -raw vm_nginx_vts_ip)

vm-ssh-angie: ## SSH into angie VM
	ssh root@$$(terraform output -raw vm_angie_ip)

check-services: ## Check services on VMs
	@for name_ip in "nginx-vts-docker:$$(terraform output -raw vm_nginx_vts_docker_ip 2>/dev/null)" "nginx-vts:$$(terraform output -raw vm_nginx_vts_ip 2>/dev/null)" "angie:$$(terraform output -raw vm_angie_ip 2>/dev/null)"; do \
		name=$${name_ip%%:*}; \
		ip=$${name_ip##*:}; \
		echo "=== $$name ($$ip) ==="; \
		echo -n "  HTTP: "; curl -s -o /dev/null -w "%{http_code}" http://$$ip/ 2>/dev/null || echo "FAIL"; \
		echo ""; \
		echo -n "  Metrics: "; curl -s -o /dev/null -w "%{http_code}" http://$$ip:9913/metrics 2>/dev/null || echo "N/A"; \
		echo ""; \
		echo -n "  Vector: "; curl -s -o /dev/null -w "%{http_code}" http://$$ip:9598/metrics 2>/dev/null || echo "N/A"; \
		echo ""; \
	done
