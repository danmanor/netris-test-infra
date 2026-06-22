.PHONY: deploy setup deploy-lab deploy-ocp deploy-osac setup-caas deploy-caas \
       deploy-vmaas deploy-bmaas \
       destroy destroy-osac destroy-ocp destroy-caas destroy-vmaas destroy-bmaas \
       connectivity prep-osac run-osac-setup vendor-update lint gather

EXTRA_VARS ?=
ANSIBLE_EXTRA = $(if $(EXTRA_VARS),-e '$(EXTRA_VARS)')

# Full shared pipeline
deploy: setup deploy-lab deploy-ocp deploy-osac

setup:
	ansible-playbook playbooks/setup-lab.yml $(ANSIBLE_EXTRA)

deploy-lab:
	ansible-playbook playbooks/deploy-lab.yml $(ANSIBLE_EXTRA)

connectivity:
	ansible-playbook playbooks/connectivity-lab.yml $(ANSIBLE_EXTRA)

deploy-ocp:
	ansible-playbook playbooks/setup-ocp.yml $(ANSIBLE_EXTRA)
	ansible-playbook playbooks/install-ocp.yml $(ANSIBLE_EXTRA)

deploy-osac: prep-osac run-osac-setup

prep-osac:
	ansible-playbook playbooks/install-osac.yml $(ANSIBLE_EXTRA)

run-osac-setup:
	@echo "=== Rebuilding Helm chart dependencies ==="
	cd /opt/osac-installer && git submodule update --init --recursive --remote && helm dependency update charts/osac/
	@echo "=== Running OSAC setup.sh with live output ==="
	cd /opt/osac-installer && source /tmp/osac-setup.env && ./scripts/setup.sh

# Per-flow targets — run after deploy
setup-caas:
	ansible-playbook playbooks/setup-caas.yml $(ANSIBLE_EXTRA)

deploy-caas:
	ansible-playbook playbooks/deploy-caas.yml $(ANSIBLE_EXTRA)

deploy-vmaas:
	@echo "VMaaS flow is not yet implemented"

deploy-bmaas:
	@echo "BMaaS flow is not yet implemented"

# Destroy targets
destroy:
	ansible-playbook playbooks/destroy.yml $(ANSIBLE_EXTRA)

destroy-osac:
	@echo "=== Tearing down OSAC ==="
	cd /opt/osac-installer && source /tmp/osac-setup.env && \
		EXTRA_SERVICES=true ./scripts/teardown.sh || true
	oc delete namespace osac-devel shared --ignore-not-found --wait=false 2>/dev/null || true
	rm -rf /opt/osac-installer
	rm -f /tmp/osac-setup.env

destroy-ocp:
	ansible-playbook playbooks/reset-ocp.yml $(ANSIBLE_EXTRA)

destroy-caas:
	@echo "CaaS teardown is not yet implemented"

destroy-vmaas:
	@echo "VMaaS teardown is not yet implemented"

destroy-bmaas:
	@echo "BMaaS teardown is not yet implemented"

# Utilities
vendor-update:
	rm -rf vendor/ansible_collections
	ansible-galaxy collection install -r requirements.yml -p vendor --force
	ansible-galaxy collection install ansible.utils -p vendor --force

lint:
	ansible-lint

gather:
	ansible-playbook playbooks/gather.yml $(ANSIBLE_EXTRA)
