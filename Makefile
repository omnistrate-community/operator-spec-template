SERVICE_NAME=Postgres Operator
SERVICE_PLAN=Postgres Operator
MAIN_RESOURCE_NAME=CNPG
ENVIRONMENT=Dev
CLOUD_PROVIDER=aws
REGION=ap-south-1
INSTANCE_ID ?=
INSTANCE_FILTER=service:$(SERVICE_NAME),plan:$(SERVICE_PLAN)
INSTANCE_ID_JQ='[.[] | .instance_id // .id // empty] | .[]'

# Load variables from .env if it exists
ifneq (,$(wildcard .env))
    include .env
    export $(shell sed 's/=.*//' .env)
endif

.PHONY: install-ctl
install-ctl:
	@brew tap omnistrate/tap
	@brew install omnistrate/tap/omnistrate-ctl

.PHONY: upgrade-ctl
upgrade-ctl:
	@brew upgrade omnistrate/tap/omnistrate-ctl
	
.PHONY: login
login:
	@cat ./.omnistrate.password | omnistrate-ctl login --email "$(OMNISTRATE_EMAIL)" --password-stdin

.PHONY: release
release:
	@omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec --product-name "$(SERVICE_NAME)" --environment "$(ENVIRONMENT)" --environment-type "$(ENVIRONMENT)" --release-as-preferred

.PHONY: create
create:
	@if [ -z "$$POSTGRESQL_PASSWORD" ]; then \
		echo "POSTGRESQL_PASSWORD environment variable is required. Set it in .env or export it before running make create."; \
		exit 1; \
	fi
	@params=$$(jq -cn --arg postgresqlPassword "$$POSTGRESQL_PASSWORD" '{postgresqlPassword: $$postgresqlPassword}'); \
	omnistrate-ctl instance create --environment "$(ENVIRONMENT)" --cloud-provider "$(CLOUD_PROVIDER)" --region "$(REGION)" --plan "$(SERVICE_PLAN)" --service "$(SERVICE_NAME)" --resource "$(MAIN_RESOURCE_NAME)" --param "$$params" --output json

.PHONY: list
list:
	@if [ -n "$(INSTANCE_ID)" ]; then \
		omnistrate-ctl instance describe "$(INSTANCE_ID)" --output json; \
	else \
		omnistrate-ctl instance list --filter="$(INSTANCE_FILTER)" --output json; \
	fi

.PHONY: delete-all
delete-all:
	@echo "Deleting all instances..."
	@instances_to_delete="$(INSTANCE_ID)"; \
	if [ -z "$$instances_to_delete" ]; then \
		instances_to_delete=$$(omnistrate-ctl instance list --filter="$(INSTANCE_FILTER)" --output json | jq -r $(INSTANCE_ID_JQ)); \
	fi; \
	if [ -z "$$instances_to_delete" ]; then \
		echo "No instances found to delete for service '$(SERVICE_NAME)' / plan '$(SERVICE_PLAN)'"; \
	fi; \
	for id in $$instances_to_delete; do \
		echo "Deleting instance: $$id"; \
		omnistrate-ctl instance delete $$id --yes; \
	done

.PHONY: delete-service
delete-service:
	@echo "Deleting service: $(SERVICE_NAME)..."
	@omnistrate-ctl service delete "$(SERVICE_NAME)"

.PHONY: destroy
destroy: 
	@$(MAKE) delete-all-wait
	@for attempt in 1 2 3; do \
		echo "Deleting service: $(SERVICE_NAME)..."; \
		output=$$(omnistrate-ctl service delete "$(SERVICE_NAME)" 2>&1); \
		status=$$?; \
		printf '%s\n' "$$output"; \
		if [ $$status -eq 0 ]; then \
			exit 0; \
		fi; \
		blocking_ids=$$(printf '%s\n' "$$output" | grep -Eo 'instance-[A-Za-z0-9]+' | sort -u | tr '\n' ' '); \
		if [ -z "$$blocking_ids" ]; then \
			exit $$status; \
		fi; \
		echo "Deleting blocking instances reported by service delete: $$blocking_ids"; \
		$(MAKE) delete-instance-ids INSTANCE_IDS="$$blocking_ids"; \
	done; \
	echo "Failed to delete service after retrying blocking instances"; \
	exit 1

.PHONY: delete-instance-ids
delete-instance-ids:
	@if [ -z "$$INSTANCE_IDS" ]; then \
		echo "INSTANCE_IDS is required"; \
		exit 1; \
	fi; \
	for id in $$INSTANCE_IDS; do \
		status=$$(omnistrate-ctl instance describe $$id --output json 2>/dev/null | jq -r '.consumptionResourceInstanceResult.status // .status // empty'); \
		if [ "$$status" = "DELETING" ]; then \
			echo "Instance $$id is already DELETING"; \
		else \
			echo "Deleting instance: $$id"; \
			omnistrate-ctl instance delete $$id --yes || true; \
		fi; \
	done; \
	echo "Waiting for blocking instances to be deleted..."; \
	while true; do \
		remaining=""; \
		for id in $$INSTANCE_IDS; do \
			if omnistrate-ctl instance describe $$id --output json >/dev/null 2>&1; then \
				remaining=$$(printf '%s\n%s\n' "$$remaining" "$$id" | awk 'NF && !seen[$$0]++'); \
			fi; \
		done; \
		if [ -z "$$remaining" ]; then \
			echo "Blocking instances deleted successfully"; \
			break; \
		fi; \
		echo "Still waiting for deletion: $$remaining"; \
		sleep 10; \
	done

.PHONY: delete-all-wait
delete-all-wait:
	@echo "Deleting all instances and waiting for completion..."
	@instances_to_delete="$(INSTANCE_ID)"; \
	if [ -z "$$instances_to_delete" ]; then \
		instances_to_delete=$$(omnistrate-ctl instance list --filter="$(INSTANCE_FILTER)" --output json | jq -r $(INSTANCE_ID_JQ)); \
	fi; \
	if [ -n "$$instances_to_delete" ]; then \
		for id in $$instances_to_delete; do \
			echo "Deleting instance: $$id"; \
			omnistrate-ctl instance delete $$id --yes; \
		done; \
		echo "Waiting for instances to be deleted..."; \
		while true; do \
			remaining=""; \
			for id in $$instances_to_delete; do \
				if omnistrate-ctl instance describe $$id --output json >/dev/null 2>&1; then \
					remaining=$$(printf '%s\n%s\n' "$$remaining" "$$id" | awk 'NF && !seen[$$0]++'); \
				fi; \
			done; \
			if [ -z "$$remaining" ]; then \
				echo "All instances deleted successfully"; \
				break; \
			fi; \
			echo "Still waiting for deletion to complete..."; \
			sleep 10; \
		done; \
	else \
		echo "No instances found to delete for service '$(SERVICE_NAME)' / plan '$(SERVICE_PLAN)'"; \
	fi
