# ==============================================================================
# NAS Ansible Project Makefile
# ==============================================================================

# Variables
INVENTORY ?= inventory.ini
PLAYBOOK ?= site.yml
REQUIREMENTS ?= requirements.yml
SOPS_AGE_KEY_FILE := age.key
SOPS_CONFIG := .sops.yaml

.PHONY: help key sops-config install run check lint encrypt clean

help: ## Display available commands
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

key: ## Generate age.key in root directory if it does not exist
	@if [ ! -f $(SOPS_AGE_KEY_FILE) ]; then \
		echo "==> $(SOPS_AGE_KEY_FILE) not found. Generating new Age key pair..."; \
		age-keygen -o $(SOPS_AGE_KEY_FILE); \
		echo "==> Age key successfully created at $(SOPS_AGE_KEY_FILE)"; \
	else \
		echo "==> Using existing $(SOPS_AGE_KEY_FILE)"; \
	fi

sops-config: key ## Generate or update .sops.yaml using public key from age.key
	@PUBKEY=$$(grep "public key:" $(SOPS_AGE_KEY_FILE) | awk '{print $$4}'); \
	if [ -z "$$PUBKEY" ]; then \
		echo "Error: Could not extract public key from $(SOPS_AGE_KEY_FILE)"; \
		exit 1; \
	fi; \
	echo "==> Updating $(SOPS_CONFIG) with Age Public Key: $$PUBKEY"; \
	printf 'creation_rules:\n  - path_regex: '\''roles/.*\\.sops\\.ya?ml'\''\n    mac_only_encrypted: true\n    age: "%s"\nstores:\n  yaml:\n    indent: 2\n' "$$PUBKEY" > $(SOPS_CONFIG)

install: key sops-config ## Generate keys, configure SOPS, and install pinned Ansible Galaxy dependencies
	@echo "==> Installing Ansible Galaxy dependencies..."
	ansible-galaxy collection install -r $(REQUIREMENTS) --force

run: key sops-config ## Run the main Ansible playbook using local age.key
	@echo "==> Executing playbook $(PLAYBOOK)..."
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

check: key sops-config ## Run playbook in dry-run/check mode
	@echo "==> Running dry-run check..."
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

lint: ## Lint Ansible files for syntax errors and best practices
	@echo "==> Linting playbook..."
	ansible-lint $(PLAYBOOK)

encrypt: key sops-config ## Find and encrypt ALL unencrypted *.sops.yaml files under roles/
	@echo "==> Searching for unencrypted roles/**/*.sops.yaml files..."
	@for file in $$(find roles -type f -name "*.sops.yaml"); do \
		if ! grep -q "^sops:" "$$file"; then \
			echo "==> Encrypting $$file..."; \
			sops --encrypt --in-place "$$file"; \
		else \
			echo "==> $$file is already encrypted. Skipping."; \
		fi; \
	done

clean: ## Clean local temporary and retry files
	@echo "==> Cleaning temporary files..."
	find . -type f -name "*.retry" -delete
	find . -type f -name "*.pyc" -delete
	rm -f $(SOPS_CONFIG)