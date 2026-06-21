.PHONY: deploy-osac setup deploy connectivity setup-ocp install-ocp install-osac caas discover-caas-hosts setup-caas vmaas bmaas destroy vendor-update lint

EXTRA_VARS ?=
ANSIBLE_EXTRA = $(if $(EXTRA_VARS),-e '$(EXTRA_VARS)')

# Shared targets — deploy OSAC on OCP (used by all flows)
deploy-osac: setup deploy setup-ocp install-ocp install-osac

setup:
	ansible-playbook playbooks/setup-lab.yml $(ANSIBLE_EXTRA)

deploy:
	ansible-playbook playbooks/deploy-lab.yml $(ANSIBLE_EXTRA)

connectivity:
	ansible-playbook playbooks/connectivity-lab.yml $(ANSIBLE_EXTRA)

setup-ocp:
	ansible-playbook playbooks/setup-ocp.yml $(ANSIBLE_EXTRA)

install-ocp:
	ansible-playbook playbooks/install-ocp.yml $(ANSIBLE_EXTRA)

install-osac: prep-osac run-osac-setup

prep-osac:
	ansible-playbook playbooks/install-osac.yml $(ANSIBLE_EXTRA)

run-osac-setup:
	@echo "=== Running OSAC setup.sh with live output ==="
	cd /opt/osac-installer && source /tmp/osac-setup.env && ./scripts/setup.sh

# Per-flow targets — run after deploy-osac
caas: discover-caas-hosts setup-caas

discover-caas-hosts:
	ansible-playbook playbooks/discover-caas-hosts.yml $(ANSIBLE_EXTRA)

setup-caas:
	ansible-playbook playbooks/setup-caas.yml $(ANSIBLE_EXTRA)

vmaas:
	@echo "VMaaS flow is not yet implemented"

bmaas:
	@echo "BMaaS flow is not yet implemented"

destroy-osac:
	@echo "=== Tearing down OSAC ==="
	cd /opt/osac-installer && source /tmp/osac-setup.env && \
		EXTRA_SERVICES=true ./scripts/teardown.sh

destroy:
	ansible-playbook playbooks/destroy.yml $(ANSIBLE_EXTRA)

vendor-update:
	rm -rf vendor/ansible_collections
	ansible-galaxy collection install -r requirements.yml -p vendor --force
	ansible-galaxy collection install ansible.utils -p vendor --force

lint:
	ansible-lint
