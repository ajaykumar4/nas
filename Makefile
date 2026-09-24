# ==============================================================================
# NAS Ansible Project Makefile
# ==============================================================================

# Variables
INVENTORY ?= inventory.ini
PLAYBOOK ?= site.yml
REQUIREMENTS ?= requirements.yml
KEY_FILE := age.key

.PHONY: help key install run check lint encrypt-role decrypt-role clean

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
		echo "==> Public Key:"; \
		grep "public key:" $(KEY_FILE) | awk '{print $$4}'; \
	else \
		echo "==> Using existing $(KEY_FILE)"; \
	fi

install: key ## Install pinned Ansible Galaxy collections from requirements.yml
	@echo "==> Installing Ansible Galaxy dependencies..."
	ansible-galaxy collection install -r $(REQUIREMENTS) --force

run: key ## Run the main Ansible playbook using local age.key
	@echo "==> Executing playbook $(PLAYBOOK)..."
	SOPS_AGE_KEY_FILE=$(KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

check: key ## Run playbook in dry-run/check mode
	@echo "==> Running dry-run check..."
	SOPS_AGE_KEY_FILE=$(KEY_FILE) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff

lint: ## Lint Ansible files for syntax errors and best practices
	@echo "==> Linting playbook..."
	ansible-lint $(PLAYBOOK)

encrypt-role: key ## Encrypt a role's secrets file (Usage: make encrypt-role ROLE=network)
	@if [ -z "$(ROLE)" ]; then \
		echo "Error: ROLE parameter is required."; \
		echo "Example: make encrypt-role ROLE=network"; \
		exit 1; \
	fi
	@PUBKEY=$$(grep "public key:" $(KEY_FILE) | awk '{print $$4}'); \
	if [ -z "$$PUBKEY" ]; then \
		echo "Error: Could not extract public key from $(KEY_FILE)"; \
		exit 1; \
	fi; \
	echo "==> Encrypting secrets for role: $(ROLE) with public key $$PUBKEY..."; \
	sops --encrypt --age $$PUBKEY roles/$(ROLE)/vars/secrets.dec.yml > roles/$(ROLE)/vars/secrets.sops.yml
	rm -f roles/$(ROLE)/vars/secrets.dec.yml

decrypt-role: key ## Edit/Decrypt a role's secrets in-place (Usage: make decrypt-role ROLE=network)
	@if [ -z "$(ROLE)" ]; then \
		echo "Error: ROLE parameter is required."; \
		echo "Example: make decrypt-role ROLE=network"; \
		exit 1; \
	fi
	@echo "==> Decrypting/Editing secrets for role: $(ROLE)..."
	SOPS_AGE_KEY_FILE=$(KEY_FILE) sops roles/$(ROLE)/vars/secrets.sops.yml

clean: ## Clean local temporary and retry files
	@echo "==> Cleaning temporary files..."
	find . -type f -name "*.retry" -delete
	find . -type f -name "*.pyc" -delete