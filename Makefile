.PHONY: all setup deploy configure install-ocp destroy

all: setup deploy configure install-ocp

setup:
	ansible-galaxy collection install -r requirements.yml -p collections

deploy: setup
	ansible-playbook playbooks/deploy-lab.yml

configure:
	ansible-playbook playbooks/configure-ocp.yml

install-ocp:
	ansible-playbook playbooks/install-ocp.yml

destroy:
	ansible-playbook playbooks/destroy.yml
