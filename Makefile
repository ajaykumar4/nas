# ==============================================================================
# NAS Ansible Project Makefile
# ==============================================================================

# Variables
INVENTORY ?= inventory.ini
PLAYBOOK ?= site.yml
REQUIREMENTS ?= requirements.yml
KEY_FILE := age.key
SOPS_CONFIG := .sops.yaml

.PHONY: help key sops-config install run check lint encrypt-role encrypt-all clean

help: ## Display available commands
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

key: ## Generate age.key in root directory if it does not exist
	@if [ ! -f $(KEY_FILE) ]; then \
		echo "==> $(KEY_FILE) not found. Generating new Age key pair..."; \
		age-keygen -o $(KEY_FILE); \
		echo "==> Age key successfully created at $(KEY_FILE)"; \
	else \
		echo "==> Using existing $(KEY_FILE)"; \
	fi

sops-config: key ## Generate or update .sops.yaml using public key from age.key
	@PUBKEY=$$(grep "public key:" $(KEY_FILE) | awk '{print $$4}'); \
	if [ -z "$$PUBKEY" ]; then \
		echo "Error: Could not extract public key from $(KEY_FILE)"; \
		exit 1; \
	fi; \
	echo "==> Updating $(SOPS_CONFIG) with Age Public Key: $$PUBKEY"; \
	printf 'creation_rules:\n  - path_regex: ".*\\.sops\\.ya?ml$$\"\n    mac_only_encrypted: true\n    age: "%s"\nstores:\n  yaml:\n    indent: 2\n' "$$PUBKEY" > $(SOPS_CONFIG)

install: key sops-config ## Generate keys, configure SOPS, and install pinned Ansible Galaxy dependencies
	@echo "==> Installing Ansible Galaxy dependencies..."
	ansible-galaxy collection install -r $(REQUIREMENTS) --force

run: key sops-config ## Run the main Ansible playbook using local age.key
	@echo "==> Executing playbook $(PLAYBOOK)..."
	SOPS_AGE_KEY_FILE=$(KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

check: key sops-config ## Run playbook in dry-run/check mode
	@echo "==> Running dry-run check..."
	SOPS_AGE_KEY_FILE=$(KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

lint: ## Lint Ansible files for syntax errors and best practices
	@echo "==> Linting playbook..."
	ansible-lint $(PLAYBOOK)

encrypt-role: key sops-config ## Encrypt all .sops.yml / .sops.yaml files in a role (Usage: make encrypt-role ROLE=network)
	@if [ -z "$(ROLE)" ]; then \
		echo "Error: ROLE parameter is required."; \
		echo "Example: make encrypt-role ROLE=network"; \
		exit 1; \
	fi
	@echo "==> Encrypting any unencrypted .sops.yml/.sops.yaml files in roles/$(ROLE)..."
	@for file in $$(find roles/$(ROLE) -type f \( -name "*.sops.yml" -o -name "*.sops.yaml" \)); do \
		if ! grep -q "sops_mac" "$$file"; then \
			echo "Encrypting $$file..."; \
			SOPS_AGE_KEY_FILE=$(KEY_FILE) sops --encrypt --in-place "$$file"; \
		else \
			echo "$$file is already encrypted. Skipping."; \
		fi; \
	done

encrypt-all: key sops-config ## Find and encrypt ALL unencrypted *.sops.yml / *.sops.yaml files across the project
	@echo "==> Searching for unencrypted .sops.yml / .sops.yaml files..."
	@for file in $$(find . -type f \( -name "*.sops.yml" -o -name "*.sops.yaml" \) ! -path "*/.*"); do \
		if ! grep -q "sops_mac" "$$file"; then \
			echo "==> Encrypting $$file..."; \
			SOPS_AGE_KEY_FILE=$(KEY_FILE) sops --encrypt --in-place "$$file"; \
		else \
			echo "==> $$file is already encrypted. Skipping."; \
		fi; \
	done

clean: ## Clean local temporary and retry files
	@echo "==> Cleaning temporary files..."
	find . -type f -name "*.retry" -delete
	find . -type f -name "*.pyc" -delete
	rm -f $(SOPS_CONFIG)