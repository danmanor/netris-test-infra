# netris-test-infra

OSAC test infrastructure that deploys and tests OpenShift Assisted Cluster on a simulated Netris Spectrum-X GPU cluster. Tests three service models: VMaaS, BMaaS (planned), and CaaS.

Uses [netris-lab](netris-lab/) as a git submodule for the underlying network infrastructure.

## Project Structure

```
roles/                          # Ansible roles (each has tasks/main.yml)
  lab_deploy/                   # Orchestrates netris-lab submodule roles
  vm_resize/                    # Resize hgx-00 VM for OCP (virsh)
  netris_configure/             # Create VPC/VNet/Subnet/NAT via Netris API
  assisted_service/             # Deploy Assisted Installer + dnsmasq DNS
  ocp_install/                  # Install OCP SNO via aicli
  osac_install/                 # Deploy OSAC (Helm + setup.sh)
  caas_discovery/               # Boot discovery VMs with InfraEnv ISO
  caas_setup/                   # Label agents, register host type, create cluster
  destroy/                      # Teardown everything
playbooks/                      # Ansible playbooks (one per workflow phase)
inventory/
  local.yml                     # Inventory (localhost, local connection)
  group_vars/all.yml            # All configuration variables
netris-lab/                     # Git submodule — see its own CLAUDE.md
vendor/                         # Vendored Ansible collections
```

## Commands

```
make all                    # prerequisites + deploy + configure + install-ocp + install-osac
make prerequisites          # Install system packages and pip tools
make deploy                 # Deploy netris-lab
make configure              # Resize OCP VM + configure Netris networking
make install-ocp            # Deploy Assisted Service + install OCP SNO
make install-osac           # Deploy OSAC + fulfillment-service
make discover-caas-hosts    # Boot hgx-01..03 with discovery ISO
make setup-caas             # Label agents + create CaaS cluster
make destroy                # Teardown all infrastructure
make vendor-update          # Refresh vendored Ansible collections
```

## Workflow Order

**VMaaS (full):** deploy → configure → install-ocp → install-osac

**CaaS (after VMaaS):** discover-caas-hosts → setup-caas

## Ansible Configuration

- Inventory: `inventory/local.yml`
- Roles path: `roles:netris-lab/roles` (both local and submodule roles)
- Collections: `vendor:netris-lab/collections`
- Netris API calls use `netris.controller.*` collection modules

## Configuration

All variables in `inventory/group_vars/all.yml`. Key sections:

- **Lab**: `netris_lab_dir`, `ew_fabric_enable`
- **OCP VM sizing**: `ocp_server_vcpu`, `ocp_server_memory_gb`, disk sizes
- **Netris networking**: `ocp_vpc_name`, `ocp_subnet_cidr`, SNAT/DNAT IPs
- **OCP install**: `ocp_version`, `ocp_cluster_name`, `ocp_base_domain`
- **OSAC**: `osac_installer_repo/branch`, `osac_namespace`, `osac_values_file`
- **Component images**: `osac_operator_image`, `fulfillment_service_image` (empty = defaults)
- **CaaS**: `caas_discovery_vm_patterns`, `caas_host_type_id`, `caas_cluster_name`, `caas_agents`

## External Dependencies

- **osac-installer** — cloned to `/opt/osac-installer` during `install-osac`
- **fulfillment-service** — cloned to `/opt/fulfillment-service`; `osac` CLI built from its Go code
- **aicli** — CLI for Red Hat Assisted Installer (pip install)
- **Credentials**: pull secret at `/root/pull-secret`, SSH key at `/root/.ssh/id_rsa.pub`

## Conventions

- Ansible roles follow standard structure: `tasks/main.yml`, `templates/`, `defaults/`
- Templates use Jinja2 (`.j2` extension)
- VM operations use `virsh`, `virt-xml`, `qemu-img` via shell/command modules
- Kubernetes resources applied via `kubernetes.core.k8s` or `oc`/`kubectl` CLI
- Waits/retries use `until` loops with `retries` and `delay`
