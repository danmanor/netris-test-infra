# netris-test-infra

Ansible automation to deploy OCP SNO on a [Netris Spectrum-X simulated lab](https://github.com/danmanor/netris-lab) and run OSAC VMaaS/CaaS end-to-end tests.

## What it does

1. **Deploy the Netris lab** — switches, softgates, servers on a single bare-metal host
2. **Resize a server VM** — scale hgx-00 to OCP SNO requirements (20 vCPU, 64 GB RAM, 100+200 GB disks)
3. **Configure Netris networking** — create VPC, VNet, Subnet via Netris controller API
4. **Install OCP SNO** — local Assisted Service + discovery ISO boot via libvirt
5. **Destroy everything** — tear down lab, assisted service, DNS

## Prerequisites

- RHEL bare-metal host with KVM/libvirt
- `ansible`, `aicli`, `virsh`, `virt-xml` installed
- [osac-aap](https://github.com/osac-project/osac-aap) cloned at `/opt/osac-aap` (provides `netris.controller` Ansible collection)
- Netris license key placed in `netris-lab/license.key`
- OpenShift pull secret at `/root/pull-secret`

## Quick start

```bash
git clone --recurse-submodules https://github.com/danmanor/netris-test-infra.git
cd netris-test-infra

# Place prerequisites
cp /path/to/license.key netris-lab/license.key
cp /path/to/pull-secret /root/pull-secret
git clone https://github.com/osac-project/osac-aap.git /opt/osac-aap

# Full flow
make all        # deploy → configure → install-ocp

# Or step by step
make deploy
make configure
make install-ocp

# Teardown
make destroy
```

## Configuration

All parameters are in [`group_vars/all.yml`](group_vars/all.yml). Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_server_vcpu` | 20 | vCPUs for OCP SNO VM |
| `ocp_server_memory_gb` | 64 | RAM in GB |
| `ocp_install_disk_gb` | 100 | Installation disk size |
| `ocp_lvm_disk_gb` | 200 | LVM storage disk size |
| `ocp_version` | 4.17 | OpenShift version |
| `ocp_cluster_name` | ocp-sno | Cluster name |
| `ocp_base_domain` | osac.local | Base DNS domain |
| `ew_fabric_enable` | 0 | East-West fabric (disabled) |

Override any variable with `-e`: `ansible-playbook playbooks/site.yml -e ocp_version=4.18`

## Playbooks

| Playbook | Roles | Purpose |
|----------|-------|---------|
| `deploy-lab.yml` | `lab_deploy` | Deploy netris-lab |
| `configure-ocp.yml` | `vm_resize`, `netris_configure` | Resize VM + create VPC/VNet/Subnet |
| `install-ocp.yml` | `assisted_service`, `ocp_install` | Install OCP SNO |
| `destroy.yml` | `destroy` | Tear down everything |
| `site.yml` | all of the above | Full end-to-end |

## CI Integration

Used by the `osac-project-netris-vmaas` workflow in the [openshift/release](https://github.com/openshift/release) step registry. CI steps SSH to an OFCIR bare-metal host, clone this repo, and run `make` targets.
