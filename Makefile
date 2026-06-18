.PHONY: all prerequisites setup deploy configure install-ocp destroy

all: setup deploy configure install-ocp

prerequisites:
	dnf install -y ansible-core python3-pip libvirt virt-install qemu-kvm git dnsmasq podman
	pip3 install aicli

setup: prerequisites
	ansible-galaxy collection install -r requirements.yml -p collections

deploy: setup
	ansible-playbook playbooks/deploy-lab.yml

configure:
	ansible-playbook playbooks/configure-ocp.yml

install-ocp:
	ansible-playbook playbooks/install-ocp.yml

destroy:
	ansible-playbook playbooks/destroy.yml
