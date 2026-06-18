.PHONY: all deploy configure install-ocp destroy

all: deploy configure install-ocp

deploy:
	ansible-playbook playbooks/deploy-lab.yml

configure:
	ansible-playbook playbooks/configure-ocp.yml

install-ocp:
	ansible-playbook playbooks/install-ocp.yml

destroy:
	ansible-playbook playbooks/destroy.yml
