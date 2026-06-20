.PHONY: all setup deploy configure install-ocp install-osac discover-caas-hosts setup-caas destroy vendor-update

all: setup deploy configure install-ocp install-osac

setup:
	ansible-playbook playbooks/setup-lab.yml

deploy:
	ansible-playbook playbooks/deploy-lab.yml

configure:
	ansible-playbook playbooks/configure-ocp.yml

install-ocp:
	ansible-playbook playbooks/install-ocp.yml

install-osac:
	ansible-playbook playbooks/install-osac.yml

discover-caas-hosts:
	ansible-playbook playbooks/discover-caas-hosts.yml

setup-caas:
	ansible-playbook playbooks/setup-caas.yml

destroy:
	ansible-playbook playbooks/destroy.yml

vendor-update:
	rm -rf vendor/ansible_collections
	ansible-galaxy collection install -r requirements.yml -p vendor --force
	ansible-galaxy collection install ansible.utils -p vendor --force
