.PHONY: help tf-init tf-apply ansible-run ansible-destroy aws-sts aws-s3-list pulumi-python-up pulumi-python-destroy pulumi-python-full-up pulumi-python-full-destroy destroy-all health smoke

CONFIRM ?= 1

define confirm
	@if [ "$(CONFIRM)" = "1" ]; then \
	  printf "About to run: %s\n%s\n\nPress Enter to continue..." "$(1)" "$(2)"; \
	  read -r _; \
	  echo ""; \
	fi
endef

help: ## show available targets
	@printf "Targets:\n"
	@while IFS= read -r line; do \
		case "$$line" in \
			[a-zA-Z0-9_-]*:*"##"*) \
				target=$${line%%:*}; \
				desc=$${line##*## }; \
				printf "  %-22s %s\n" "$$target" "$$desc"; \
				;; \
		esac; \
	done < $(firstword $(MAKEFILE_LIST))

tf-init: ## terraform init (offline cache)
	$(call confirm,tf-init,Initialize Terraform using the offline provider cache.)
	@tf-init

tf-apply: ## terraform apply
	$(call confirm,tf-apply,Apply Terraform for both regions against LocalStack.)
	@tf-apply

ansible-run: ## run Ansible playbook
	$(call confirm,ansible-run,Run the Ansible playbook against LocalStack.)
	@ansible-run

ansible-destroy: ## destroy Ansible-created resources
	$(call confirm,ansible-destroy,Remove resources created by the Ansible playbook.)
	@ansible-destroy

aws-sts: ## aws sts get-caller-identity
	$(call confirm,aws-sts,Query the LocalStack STS endpoint.)
	@aws sts get-caller-identity

aws-s3-list: ## aws s3api list-buckets
	$(call confirm,aws-s3-list,List all S3 buckets in LocalStack.)
	@aws s3api list-buckets

PULUMI_STACK ?= dev
PULUMI_PY_DIR := /home/sandbox/workspace/pulumi/python

pulumi-python-init:
	@pulumi-python -C $(PULUMI_PY_DIR) stack select $(PULUMI_STACK) || pulumi-python -C $(PULUMI_PY_DIR) stack init $(PULUMI_STACK)

pulumi-python-up: ## pulumi up (python)
	$(call confirm,pulumi-python-up,Preview and apply the Pulumi Python stack in LocalStack.)
	@pulumi-python -C $(PULUMI_PY_DIR) stack select $(PULUMI_STACK) || pulumi-python -C $(PULUMI_PY_DIR) stack init $(PULUMI_STACK)
	@pulumi-python -C $(PULUMI_PY_DIR) up -y --stack $(PULUMI_STACK)

pulumi-python-destroy: ## pulumi destroy (python)
	$(call confirm,pulumi-python-destroy,Destroy the Pulumi Python stack in LocalStack.)
	@pulumi-python -C $(PULUMI_PY_DIR) stack select $(PULUMI_STACK) || pulumi-python -C $(PULUMI_PY_DIR) stack init $(PULUMI_STACK)
	@pulumi-python -C $(PULUMI_PY_DIR) destroy -y --stack $(PULUMI_STACK)

pulumi-python-full-up: ## pulumi up (python, full stack)
	$(call confirm,pulumi-python-full-up,Preview and apply the full Pulumi Python stack in LocalStack.)
	@pulumi-python -C $(PULUMI_PY_DIR) stack select full || pulumi-python -C $(PULUMI_PY_DIR) stack init full
	@pulumi-python -C $(PULUMI_PY_DIR) config set simulateUnsupported false --stack full
	@pulumi-python -C $(PULUMI_PY_DIR) up -y --stack full

pulumi-python-full-destroy: ## pulumi destroy (python, full stack)
	$(call confirm,pulumi-python-full-destroy,Destroy the full Pulumi Python stack in LocalStack.)
	@pulumi-python -C $(PULUMI_PY_DIR) stack select full || pulumi-python -C $(PULUMI_PY_DIR) stack init full
	@pulumi-python -C $(PULUMI_PY_DIR) destroy -y --stack full

destroy-all: ## destroy Pulumi stacks and wipe all S3 buckets
	$(call confirm,destroy-all,Destroy all Pulumi stacks and remove every S3 bucket in LocalStack.)
	@if [ -z "$${LOCALSTACK_ENDPOINT:-}" ]; then echo "LOCALSTACK_ENDPOINT not set"; exit 1; fi
	@echo "Destroying Pulumi stacks..."
	@$(MAKE) pulumi-python-destroy || echo "pulumi-python-destroy failed (continuing)"
	@$(MAKE) pulumi-python-full-destroy || echo "pulumi-python-full-destroy failed (continuing)"
	@echo "Wiping S3 buckets..."
	@buckets=$$(aws --endpoint-url "$$LOCALSTACK_ENDPOINT" s3api list-buckets --query 'Buckets[].Name' --output text); \
	if [ -n "$$buckets" ]; then \
	  for b in $$buckets; do \
	    aws --endpoint-url "$$LOCALSTACK_ENDPOINT" s3 rm "s3://$$b" --recursive >/dev/null 2>&1 || true; \
	    aws --endpoint-url "$$LOCALSTACK_ENDPOINT" s3api delete-bucket --bucket "$$b" >/dev/null 2>&1 || true; \
	  done; \
	fi; \
	echo "destroy-all: done"

health: ## sandbox healthcheck (awscli against LocalStack)
	$(call confirm,health,Run a basic AWS CLI health check against LocalStack.)
	@if [ -z "$${LOCALSTACK_ENDPOINT:-}" ]; then echo "LOCALSTACK_ENDPOINT not set"; exit 1; fi
	@aws --endpoint-url "$$LOCALSTACK_ENDPOINT" sts get-caller-identity >/dev/null
	@aws --endpoint-url "$$LOCALSTACK_ENDPOINT" s3api list-buckets >/dev/null
	@echo "sandbox health: ok"

smoke: ## sandbox awscli smoke test
	$(call confirm,smoke,Run a simple AWS CLI smoke test against LocalStack.)
	@if [ -z "$${LOCALSTACK_ENDPOINT:-}" ]; then echo "LOCALSTACK_ENDPOINT not set"; exit 1; fi
	@aws --endpoint-url "$$LOCALSTACK_ENDPOINT" sts get-caller-identity >/dev/null
	@aws --endpoint-url "$$LOCALSTACK_ENDPOINT" s3api list-buckets >/dev/null
	@echo "sandbox awscli: ok"
