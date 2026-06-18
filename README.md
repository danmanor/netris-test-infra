# netris-test-infra

Ansible automation to deploy OCP SNO on a [Netris Spectrum-X simulated lab](https://github.com/danmanor/netris-lab) and run OSAC VMaaS/CaaS end-to-end tests.

## Architecture

The [netris-lab](https://github.com/danmanor/netris-lab) deploys a full simulated Spectrum-X GPU cluster network on a single bare-metal host using KVM/libvirt:

- **Netris controller** on K3s — manages all network devices via REST/gRPC API
- **~13 switch VMs** (Cumulus Linux) — leaf/spine fabric for North-South connectivity
- **4 softgate VMs** — provide NAT/L4LB and BGP peering for internet access
- **4 server VMs** (hgx-00 to hgx-03) — simulated GPU servers, managed by Netris

This repo takes the first server (hgx-00), resizes it for OCP, configures Netris networking (VPC, VNet, Subnet), and installs OpenShift SNO on it using the Assisted Installer.

```
Bare-metal host
└── netris-lab (~50 VMs)
    ├── Netris controller (K3s)
    ├── Switches (leaf/spine fabric)
    ├── Softgates (NAT → internet)
    └── hgx-00 (resized: 20 vCPU, 64G RAM)
        ├── VPC/VNet/Subnet configured via Netris API
        ├── OCP SNO installed via Assisted Installer
        └── OSAC deployed on top
```

Internet access for OCP image pulls flows through: hgx-00 → NS VNet → softgate SNAT → host iptables masquerade → internet.

## Prerequisites

- **RHEL bare-metal host** with KVM/libvirt support
- **Resources**: ~32+ CPU cores, 128+ GB RAM (lab VMs + OCP SNO VM)
- **Tools installed**: `ansible`, `aicli`, `virsh`, `virt-xml`, `git`
- **Netris license key** — place in `netris-lab/license.key`
- **OpenShift pull secret** — place at `/root/pull-secret` (or set `pull_secret_path`)
- **SSH key pair** at `/root/.ssh/id_rsa` and `/root/.ssh/id_rsa.pub`

The [osac-aap](https://github.com/osac-project/osac-aap) collection (provides `netris.controller` Ansible roles) is cloned automatically by the `netris_configure` role. The netris-lab prerequisites (Go, Pulumi, OpenTofu, etc.) are installed automatically by `make deploy`.

## Quick start

```bash
git clone --recurse-submodules https://github.com/danmanor/netris-test-infra.git
cd netris-test-infra

# Place prerequisites
cp /path/to/license.key netris-lab/license.key
cp /path/to/pull-secret /root/pull-secret

# Full flow (deploy lab → configure networking → install OCP)
make all

# Or step by step
make deploy        # Deploy netris-lab (~45-90 min)
make configure     # Resize VM + create VPC/VNet/Subnet (~10 min)
make install-ocp   # Install OCP SNO via Assisted Installer (~30-60 min)

# Teardown
make destroy
```

After `make install-ocp`, the kubeconfig is at `/root/.kube/config`.

## Configuration

All parameters are in [`group_vars/all.yml`](group_vars/all.yml). Override with `-e`:

```bash
ansible-playbook playbooks/site.yml -e ocp_version=4.18
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
| `ocp_version` | `4.17` | OpenShift version to install |
| `ocp_cluster_name` | `ocp-sno` | Cluster name |
| `ocp_base_domain` | `osac.local` | Base DNS domain (resolved via local dnsmasq) |
| `pull_secret_path` | `/root/pull-secret` | Path to OpenShift pull secret |
| `ssh_public_key_path` | `/root/.ssh/id_rsa.pub` | SSH public key for node access |

### Netris Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_vpc_name` | `ocp-sno` | VPC name in Netris |
| `ocp_vnet_name` | `ocp-sno-vnet` | VNet name in Netris |
| `ocp_subnet_cidr` | `192.168.40.0/24` | Subnet CIDR for OCP server |
| `ocp_gateway` | `192.168.40.1/24` | VNet gateway |
| `ocp_node_ip` | `192.168.40.2` | Expected OCP node IP (used for DNS) |
| `ew_fabric_enable` | `0` | East-West fabric (0=disabled) |

### Netris Controller

| Variable | Default | Description |
|----------|---------|-------------|
| `netris_controller_url` | `http://localhost:9443` | Controller API URL |
| `netris_username` | `netris` | API username |
| `netris_password` | `MaqfC1JBM7zasPE2doVT` | API password (lab default) |

## Playbooks

| Playbook | Roles | Purpose |
|----------|-------|---------|
| `deploy-lab.yml` | `lab_deploy` | Deploy netris-lab (make setup + deploy + verify) |
| `configure-ocp.yml` | `vm_resize`, `netris_configure` | Resize hgx-00 VM + create VPC/VNet/Subnet |
| `install-ocp.yml` | `assisted_service`, `ocp_install` | Start Assisted Service, install OCP SNO |
| `destroy.yml` | `destroy` | Tear down lab + Assisted Service + DNS |
| `site.yml` | all of the above | Full end-to-end flow |

## CI Integration

Used by the `osac-project-netris-vmaas` workflow in the [openshift/release](https://github.com/openshift/release) step registry. CI steps SSH to an OFCIR bare-metal host, clone this repo with `--recurse-submodules`, and run `make` targets.

## Known Limitations

- **VNet port format**: The `ocp_server_ports` variable uses `eth9@hgx-pod00-su0-h00` notation from Terraform. The exact format accepted by the Netris API may differ and needs verification.
- **OCP node IP**: `ocp_node_ip` (192.168.40.2) is a placeholder. The actual IP depends on Netris IPAM assignment and may need to be discovered dynamically.
- **Assisted Service reachability**: The discovery agent on hgx-00 needs to reach the Assisted Service on the host. If the default `aicli create onprem` IP detection doesn't work, set `SERVICE_BASE_URL` to the br-mgmt host IP (192.168.16.254).
