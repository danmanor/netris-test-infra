# netris-test-infra

Ansible automation to deploy OCP SNO on a [Netris Spectrum-X simulated lab](https://github.com/danmanor/netris-lab) and run OSAC VMaaS/CaaS/BMaaS end-to-end tests.

## Architecture

The [netris-lab](https://github.com/danmanor/netris-lab) deploys a full simulated Spectrum-X GPU cluster network on a single bare-metal host using KVM/libvirt:

- **Netris controller** on K3s — manages all network devices via REST/gRPC API
- **~13 switch VMs** (Cumulus Linux) — leaf/spine fabric for North-South connectivity
- **4 softgate VMs** — provide NAT/L4LB and BGP peering for internet access
- **4 server VMs** (hgx-00 to hgx-03) — simulated GPU servers, managed by Netris

This repo takes the first server (hgx-00), resizes it for OCP, configures Netris networking (VPC, VNet, Subnet), and installs OpenShift SNO on it using the Assisted Installer. For CaaS testing, the remaining three servers (hgx-01 to hgx-03) are booted with a discovery ISO and registered as agents for cluster provisioning.

```
Bare-metal host
└── netris-lab (~15 VMs)
    ├── Netris controller (K3s)
    ├── Switches (leaf/spine fabric)
    ├── Softgates (NAT → internet)
    ├── hgx-00 (resized: 20 vCPU, 64G RAM)
    │   ├── VPC/VNet/Subnet configured via Netris API
    │   ├── OCP SNO installed via Assisted Installer
    │   └── OSAC deployed on top
    └── hgx-01..03 (CaaS only: 4 vCPU, 16G RAM, 100G disk)
        ├── Booted with discovery ISO from InfraEnv
        ├── Registered as agents with resource_class + netris.server/name
        └── Used to provision a CaaS cluster via fulfillment API
```

Internet access for OCP image pulls flows through: hgx-00 → NS VNet → softgate SNAT → host iptables masquerade → internet.

## Prerequisites

- **Bare-metal host** running RHEL 9.x or Rocky Linux 9.x with KVM support
- **Resources**: ~32+ CPU cores, 128+ GB RAM (lab VMs + OCP SNO VM)
- **Netris license key** — place at repo root as `license.key` (used by `make deploy`)
- **OSAC/AAP license** — place at repo root as `license.zip` (used by `make install-osac`)
- **OpenShift pull secret** — place at `/root/pull-secret` or set `pull_secret_path` (used by `make install-ocp` and `make discover-caas-hosts`; download from [console.redhat.com](https://console.redhat.com/openshift/downloads))

All system packages (ansible, libvirt, qemu-kvm, openvpn, Go, Pulumi, OpenTofu, etc.) and OCP/OSAC tools (aicli, oc, helm, osac CLI) are installed automatically by `make setup` and the Ansible roles. A pre-flight check validates all required files (Netris license, AAP license, pull secret, SSH key), KVM support, and minimum memory before deploying.

## Quick start

```bash
git clone --recurse-submodules https://github.com/danmanor/netris-test-infra.git
cd netris-test-infra

# Place prerequisites
cp /path/to/license.key ./license.key
cp /path/to/license.zip ./license.zip
cp /path/to/pull-secret /root/pull-secret

# Full VMaaS flow (setup → deploy lab → configure networking → install OCP → install OSAC)
make all

# Or step by step
make setup         # Install prerequisites + cache images + OCP/OSAC tools (~20 min)
make deploy        # Deploy netris-lab (~45-90 min)
make ocp-setup     # Resize VM + create VPC/VNet/Subnet (~10 min)
make install-ocp   # Install OCP SNO via Assisted Installer (~30-60 min)
make install-osac  # Install OSAC on OCP (~30 min)

# Re-run connectivity (VPN, BGP, softgate agents) without full redeploy
make connectivity

# CaaS additional steps (after make all)
make discover-caas-hosts  # Create InfraEnv, boot hgx1-3 with discovery ISO (~15 min)
make setup-caas           # Annotate agents, create host type + cluster, wait for ready (~60 min)

# Teardown
make destroy
```

After `make install-ocp`, the kubeconfig is at `/root/.kube/config`.

After `make deploy`, the Netris controller UI is available at `https://<hypervisor>:9443`. After `make install-ocp`, the Assisted Installer UI is available at `http://<hypervisor>:8080`.

## Configuration

All parameters are in [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml). Override with `-e`:

```bash
ansible-playbook playbooks/site.yml -e ocp_version=4.21
```

### OCP Server VM

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_vm_name_pattern` | `hgx-pod00-su0-h00` | VM name pattern to find in libvirt |
| `ocp_server_vcpu` | `20` | vCPUs for OCP SNO VM |
| `ocp_server_memory_gb` | `64` | RAM in GB |
| `ocp_install_disk_gb` | `100` | Installation disk size in GB |
| `ocp_lvm_disk_gb` | `200` | Extra LVM storage disk in GB |

### OCP Installation

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_version` | `4.21` | OpenShift version to install |
| `ocp_cluster_name` | `ocp-sno` | Cluster name |
| `ocp_base_domain` | `osac.local` | Base DNS domain (resolved via local dnsmasq) |
| `pull_secret_path` | `/root/pull-secret` | Path to OpenShift pull secret |
| `ssh_public_key_path` | `/root/.ssh/id_rsa.pub` | SSH public key for node access |
| `assisted_service_url` | `http://localhost:8090` | Assisted Installer service URL |
| `assisted_service_ip` | `198.51.100.9` | IP address for Assisted Service access |

### Netris Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_vpc_name` | `ocp-sno` | VPC name in Netris |
| `ocp_vnet_name` | `ocp-sno-vnet` | VNet name in Netris |
| `ocp_subnet_cidr` | `192.168.40.0/24` | Subnet CIDR for OCP server |
| `ocp_gateway` | `192.168.40.1/24` | VNet gateway |
| `ocp_node_ip` | `192.168.40.2` | Expected OCP node IP (used for DNS) |
| `ocp_snat_ip` | `198.51.100.1` | SNAT IP for outbound internet access |
| `ocp_dnat_ip` | `198.51.100.2` | DNAT IP for inbound access to OCP API/apps |
| `ew_fabric_enable` | `0` | East-West fabric (0=disabled) |

### Netris Controller

| Variable | Default | Description |
|----------|---------|-------------|
| `netris_username` | `netris` | API username |
| `netris_password` | `netris` | API password |
| `netris_validate_certs` | `false` | Validate TLS certificates for Netris API |

The controller URL is discovered dynamically by the `netris_configure` role from the running K3s service.

### OSAC / Fulfillment Service

| Variable | Default | Description |
|----------|---------|-------------|
| `osac_installer_repo` | `https://github.com/osac-project/osac-installer.git` | osac-installer Git repo |
| `osac_installer_branch` | `main` | Branch to clone |
| `osac_namespace` | `osac` | Kubernetes namespace for OSAC |
| `osac_kustomize_overlay` | `vmaas-ci` | Kustomize overlay directory |
| `osac_values_file` | `values/vmaas-ci/values.yaml` | Helm values file path (relative to installer dir) |
| `osac_license_path` | `license.zip` (repo root) | AAP license zip file path |
| `osac_operator_image` | `""` (use installer default) | Override OSAC operator image |
| `fulfillment_service_image` | `""` (use installer default) | Override fulfillment-service image |
| `osac_aap_image` | `""` (use installer default) | Override AAP bootstrap image |
| `fulfillment_service_repo` | `https://github.com/osac-project/fulfillment-service.git` | fulfillment-service Git repo (for osac CLI) |
| `fulfillment_service_branch` | `main` | Branch to clone |

### CaaS Discovery

| Variable | Default | Description |
|----------|---------|-------------|
| `caas_discovery_vm_patterns` | `[hgx-pod00-su0-h01..h03]` | VM name patterns for discovery servers |
| `caas_discovery_vcpu` | `4` | vCPUs per discovery server |
| `caas_discovery_memory_mb` | `16384` | Memory in MB (16 GB) |
| `caas_discovery_disk_gb` | `100` | Boot disk size in GB |
| `caas_discovery_infraenv_name` | `caas-infraenv` | InfraEnv CR name |

### CaaS Setup

| Variable | Default | Description |
|----------|---------|-------------|
| `caas_host_type_id` | `ci-worker` | Host type ID registered in fulfillment API |
| `caas_cluster_catalog_item` | `hosted_cluster_offering` | Catalog item for cluster creation |
| `caas_cluster_name` | `caas-ci-cluster` | Name for the created cluster |
| `caas_agents` | `[{vm_pattern, netris_server_name}]` | Agent-to-Netris-server mapping |

## Playbooks

| Playbook | Roles | Purpose |
|----------|-------|---------|
| `setup-lab.yml` | `lab_setup` | Install prerequisites, cache images, install OCP/OSAC tools |
| `deploy-lab.yml` | `lab_deploy` | Deploy netris-lab (K3s → topology → cloudsim → connectivity → verify) |
| `connectivity-lab.yml` | (inline) `connectivity` | Re-run lab connectivity (VPN, BGP, softgate agents) |
| `configure-ocp.yml` | `vm_resize`, `netris_configure` | Resize hgx-00 VM + create VPC/VNet/Subnet |
| `install-ocp.yml` | `assisted_service`, `ocp_install` | Start Assisted Service, install OCP SNO |
| `install-osac.yml` | `osac_install` | Install OSAC on OCP SNO |
| `discover-caas-hosts.yml` | `caas_discovery` | Create InfraEnv, boot hgx1-3 with discovery ISO |
| `setup-caas.yml` | `caas_setup` | Annotate agents, create host type + cluster |
| `destroy.yml` | `destroy` | Tear down lab + Assisted Service + DNS |
| `site.yml` | all common roles | Full end-to-end flow (VMaaS) |

### How setup and deploy work

Setup and deploy are split into two phases. The `lab_setup` role (run by `setup-lab.yml`) handles installation and caching. The `lab_deploy` role (run by `deploy-lab.yml`) handles infrastructure deployment. Both roles use `include_role` to run netris-lab submodule roles directly in the parent Ansible process.

**`setup-lab.yml` (lab_setup role):**

1. **Pre-flight checks** — validates Netris license, OSAC/AAP license, pull secret, SSH key, KVM support, and minimum memory
2. **prerequisites** — installs system packages, Go, Pulumi, OpenTofu, configures libvirt/bridges
3. **cache** — pre-downloads container and cloud images via skopeo
4. **OCP/OSAC tools** — installs podman, dnsmasq, aicli, oc, helm, Go, and builds the osac CLI from fulfillment-service

**`deploy-lab.yml` (lab_deploy role):**

1. **Pre-flight checks** — re-validates environment
2. **k3s_controller** — deploys K3s and Netris controller Helm chart
3. **topology** — creates network topology in Netris API via OpenTofu
4. **cloudsim** — provisions KVM VMs via Pulumi
5. **connectivity** — sets up VPN, socat forwarding, ISP BGP, softgate agents
6. **verify** — health checks (switches, softgates, E-BGP, license, API)

## CI Integration

Used by CI workflows in the [openshift/release](https://github.com/openshift/release) step registry:

- **`osac-project-netris-vmaas`** — VMaaS e2e: deploy lab → configure → OCP install → OSAC install → VMaaS tests
- **`osac-project-netris-caas`** — CaaS e2e: same base + discover agents → setup CaaS cluster → CaaS tests

CI steps SSH to an OFCIR bare-metal host, clone this repo with `--recurse-submodules`, and run `make` targets.
