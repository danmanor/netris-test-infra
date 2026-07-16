.PHONY: deploy deploy-full deploy-fast setup bootstrap disk-setup deploy-bg deploy-bg-full \
       deploy-lab deploy-ocp deploy-ocp-snapshot deploy-osac \
       restore-ocp-snapshot snapshot-refresh prep-snapshot-refresh run-snapshot-refresh post-snapshot-refresh \
       setup-caas deploy-caas \
       deploy-vmaas deploy-bmaas post-install \
       destroy destroy-full destroy-bg destroy-osac destroy-ocp destroy-caas destroy-vmaas destroy-bmaas \
       connectivity prep-osac run-osac-setup post-osac vendor-update lint \
       gather gather-lab gather-caas \
       cleanup-dns

EXTRA_VARS ?=
ANSIBLE_EXTRA = $(if $(EXTRA_VARS),-e '$(EXTRA_VARS)')

# Remote deploy variables (used by deploy-bg)
SERVER ?=
PASSWORD ?=
LAB_NAME ?=
PULL_SECRET ?=
LICENSE_KEY ?=
LICENSE_ZIP ?=
AWS_ACCESS_KEY_ID ?=
AWS_SECRET_ACCESS_KEY ?=
export SERVER PASSWORD LAB_NAME PULL_SECRET LICENSE_KEY LICENSE_ZIP AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# Full shared pipeline
deploy: deploy-lab deploy-ocp deploy-osac

setup:
	ansible-playbook playbooks/setup.yml $(ANSIBLE_EXTRA)

deploy-lab:
	ansible-playbook playbooks/deploy-lab.yml $(ANSIBLE_EXTRA)

connectivity:
	ansible-playbook playbooks/connectivity-lab.yml $(ANSIBLE_EXTRA)

deploy-ocp:
	ansible-playbook playbooks/setup-ocp.yml $(ANSIBLE_EXTRA)
	ansible-playbook playbooks/install-ocp.yml $(ANSIBLE_EXTRA)

deploy-osac: prep-osac run-osac-setup post-osac

prep-osac:
	ansible-playbook playbooks/prep-osac.yml $(ANSIBLE_EXTRA)

run-osac-setup:
	@echo "=== Installing OSAC via Helm (make install) ==="
	cd /opt/osac-installer && make install \
		INSTALLER_NAMESPACE=$(or $(OSAC_NAMESPACE),$(shell grep '^osac_namespace:' inventory/group_vars/all.yml | awk '{print $$2}' | tr -d '"')) \
		VALUES_FILE=$(or $(OSAC_VALUES_FILE),$(shell grep '^osac_values_file:' inventory/group_vars/all.yml | awk '{print $$2}' | tr -d '"'))

post-osac:
	ansible-playbook playbooks/post-osac.yml $(ANSIBLE_EXTRA)

# Per-flow targets — run after deploy
setup-caas:
	ansible-playbook playbooks/setup-caas.yml $(ANSIBLE_EXTRA)

deploy-caas:
	ansible-playbook playbooks/deploy-caas.yml $(ANSIBLE_EXTRA)

deploy-vmaas:
	@echo "VMaaS flow is not yet implemented"

deploy-bmaas:
	@echo "BMaaS flow is not yet implemented"

# --- Baremetal remote deploy additions ---

# Full pipeline including CaaS + post-install
deploy-full: setup deploy setup-caas deploy-caas post-install

# Remote background deploy (from laptop → server in tmux)
deploy-bg:
	@DEPLOY_TARGET=deploy scripts/deploy-remote.sh

# Remote full deploy including CaaS (from laptop → server in tmux)
deploy-bg-full:
	@DEPLOY_TARGET=deploy-full scripts/deploy-remote.sh

# Bootstrap: minimal host packages required before Ansible can run
bootstrap:
	@echo "=== Installing minimal host prerequisites ==="
	dnf install -y git make ansible-core python3-pip sshpass tmux
	pip3 install ansible bcrypt netaddr

# Disk setup: detect largest unused disk, mount, symlink data dirs
disk-setup:
	ansible-playbook playbooks/disk-setup.yml $(ANSIBLE_EXTRA)

# Post-install: fix OSAC UI external access + generate access markdown
post-install:
	ansible-playbook playbooks/post-install.yml $(ANSIBLE_EXTRA)

# Snapshot-based fast deployment
deploy-fast: deploy-lab deploy-ocp-snapshot

deploy-ocp-snapshot: restore-ocp-snapshot snapshot-refresh

restore-ocp-snapshot:
	ansible-playbook playbooks/restore-ocp-snapshot.yml $(ANSIBLE_EXTRA)

snapshot-refresh: prep-snapshot-refresh run-snapshot-refresh post-snapshot-refresh

prep-snapshot-refresh:
	ansible-playbook playbooks/prep-snapshot-refresh.yml $(ANSIBLE_EXTRA)

run-snapshot-refresh:
	@echo "=== Running OSAC refresh with live output ==="
	cd /opt/osac-installer && \
		KUBECONFIG=/root/.kube/config \
		VALUES_FILE=$(or $(SNAPSHOT_VALUES_FILE),values/caas-ci/values.yaml) \
		INSTALLER_NAMESPACE=$(or $(SNAPSHOT_NAMESPACE),osac-devel) \
		python3 -u scripts/refresh-after-snapshot.py

post-snapshot-refresh:
	ansible-playbook playbooks/post-snapshot-refresh.yml $(ANSIBLE_EXTRA)

# Destroy targets
destroy:
	ansible-playbook playbooks/destroy.yml $(ANSIBLE_EXTRA)

destroy-full:
	ansible-playbook playbooks/destroy-full.yml $(ANSIBLE_EXTRA)

destroy-bg:
	sshpass -p '$(PASSWORD)' ssh -o StrictHostKeyChecking=no root@$(SERVER) \
		"cd /root/netris-test-infra && make destroy-full 2>&1 | tee /root/destroy.log"

destroy-osac:
	@echo "=== Tearing down OSAC ==="
	@if [ -d /opt/osac-installer ]; then \
		cd /opt/osac-installer && make uninstall \
			INSTALLER_NAMESPACE=$(or $(OSAC_NAMESPACE),$(shell grep '^osac_namespace:' inventory/group_vars/all.yml | awk '{print $$2}' | tr -d '"')) \
			VALUES_FILE=$(or $(OSAC_VALUES_FILE),$(shell grep '^osac_values_file:' inventory/group_vars/all.yml | awk '{print $$2}' | tr -d '"')) \
			2>/dev/null || true; \
	fi
	rm -rf /opt/osac-installer

destroy-ocp:
	ansible-playbook playbooks/destroy-ocp.yml $(ANSIBLE_EXTRA)

destroy-caas:
	ansible-playbook playbooks/destroy-caas.yml $(ANSIBLE_EXTRA)

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

gather-lab:
	ansible-playbook playbooks/gather-lab.yml $(ANSIBLE_EXTRA)

gather-caas:
	ansible-playbook playbooks/gather-caas.yml $(ANSIBLE_EXTRA)

cleanup-dns:
	ansible-playbook playbooks/cleanup-dns.yml $(ANSIBLE_EXTRA)
