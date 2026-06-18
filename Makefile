.PHONY: all prerequisites deploy configure install-ocp destroy vendor-update

all: prerequisites deploy configure install-ocp

prerequisites:
	dnf install -y ansible-core python3-pip libvirt virt-install qemu-kvm git dnsmasq podman
	pip3 install aicli netaddr

deploy: prerequisites
	ansible-playbook playbooks/deploy-lab.yml

configure:
	ansible-playbook playbooks/configure-ocp.yml

install-ocp:
	ansible-playbook playbooks/install-ocp.yml

destroy:
	ansible-playbook playbooks/destroy.yml

vendor-update:
	rm -rf vendor/ansible_collections
	ansible-galaxy collection install -r requirements.yml -p vendor --force
	ansible-galaxy collection install ansible.utils -p vendor --force
