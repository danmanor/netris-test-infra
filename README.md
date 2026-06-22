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
- **Netris license key** — place at repo root as `license.key`
- **OSAC/AAP license** — place at repo root as `license.zip`
- **OpenShift pull secret** — place at `/root/pull-secret` (or set `pull_secret_path`; download from [console.redhat.com](https://console.redhat.com/openshift/downloads))

All system packages and tools are installed automatically by `make setup`. A pre-flight check validates all required files, KVM support, and minimum memory before deploying.

## Quick Start

```bash
git clone --recurse-submodules https://github.com/danmanor/netris-test-infra.git
cd netris-test-infra

# Place prerequisites
cp /path/to/license.key ./license.key
cp /path/to/license.zip ./license.zip
cp /path/to/pull-secret /root/pull-secret

# Full deployment (setup → lab → OCP → OSAC)
make deploy

# Then run a test flow
make setup-caas    # CaaS setup: discover hosts, label agents, register host type
make deploy-caas   # CaaS: create cluster
```

After `make deploy-ocp`, the kubeconfig is at `/root/.kube/config`.

## Make Targets

### Deploy

| Target | Description | Time |
|--------|-------------|------|
| `make deploy` | Full pipeline: setup → deploy-lab → deploy-ocp → deploy-osac | ~2-3 hrs |
| `make setup` | Install prerequisites, cache images, build OCP/OSAC tools | ~10 min |
| `make deploy-lab` | Deploy netris-lab (K3s, topology, VMs, connectivity) | ~30 min |
| `make deploy-ocp` | Resize OCP VM + Netris networking + Assisted Service + OCP SNO | ~35-65 min |
| `make deploy-osac` | Prepare OSAC overlay + run setup.sh (live output) | ~30-60 min |

### CaaS (run after deploy)

| Target | Description | Time |
|--------|-------------|------|
| `make setup-caas` | Discover hosts, label agents, register host type, configure osac CLI | ~30 min |
| `make deploy-caas` | Create CaaS cluster using `ocp_ci_small` template | ~60 min |

### Other flows (run after deploy)

| Target | Description | Time |
|--------|-------------|------|
| `make deploy-vmaas` | VMaaS flow (not yet implemented) | — |
| `make deploy-bmaas` | BMaaS flow (not yet implemented) | — |

### Destroy

| Target | Description |
|--------|-------------|
| `make destroy` | Tear down everything: OSAC + OCP artifacts + netris-lab |
| `make destroy-osac` | Tear down OSAC: helm releases, operators, CRDs, namespaces (live output) |
| `make destroy-ocp` | Reset OCP for reinstall: delete cluster, recreate disk, boot VM |
| `make destroy-caas` | CaaS teardown (not yet implemented) |
| `make destroy-vmaas` | VMaaS teardown (not yet implemented) |
| `make destroy-bmaas` | BMaaS teardown (not yet implemented) |

### Recovery and Utilities

| Target | Description |
|--------|-------------|
| `make connectivity` | Re-run lab connectivity (VPN, BGP, softgates) without full redeploy |
| `make run-osac-setup` | Re-run just setup.sh with live output (after prep-osac has run) |
| `make prep-osac` | Ansible-only OSAC prep (clone, overlay, secrets, env file) — no setup.sh |
| `make vendor-update` | Refresh vendored Ansible collections |
| `make lint` | Run ansible-lint |

### Typical Workflows

**First deploy on a fresh server:**
```bash
make deploy         # does everything
```

**Re-deploy OSAC after code changes:**
```bash
make destroy-osac   # tear down OSAC (keeps OCP and lab)
make deploy-osac    # redeploy
```

**Re-install OCP (e.g., different version):**
```bash
make destroy-ocp    # delete cluster, recreate disk
make deploy-ocp     # reinstall
```

**Fix lab connectivity issues (e.g., softgate/E-BGP):**
```bash
make connectivity   # re-runs VPN, socat, ISP FRR, softgate agents
```

**Deploy CaaS after OSAC is up:**
```bash
make setup-caas     # discover hosts, label agents, register host type
make deploy-caas    # create cluster
```

**Rebuild from scratch:**
```bash
make destroy        # tear down everything
make deploy         # full redeploy
```

## Accessing OCP Routes

After `make deploy-osac`, a socat forwarder on port 9444 provides access to OCP routes (AAP UI, OCP console, fulfillment API) from external browsers. Port 443 is intercepted by K3s svclb (Netris controller), so 9444 is used instead.

Add to your local `/etc/hosts`:
```
<server-ip>  osac-aap-osac-devel.apps.ocp-sno.osac.local
<server-ip>  console-openshift-console.apps.ocp-sno.osac.local
<server-ip>  fulfillment-api-osac-devel.apps.ocp-sno.osac.local
```

Then browse to `https://osac-aap-osac-devel.apps.ocp-sno.osac.local:9444` (accept the self-signed cert).

| Service | URL |
|---------|-----|
| AAP UI | `https://osac-aap-osac-devel.apps.ocp-sno.osac.local:9444` |
| OCP Console | `https://console-openshift-console.apps.ocp-sno.osac.local:9444` |
| Assisted Installer UI | `http://<server-ip>:8080` |
| Netris Controller | `http://<server-ip>:9443` |

## How deploy-osac Works

`make deploy-osac` runs in two phases for live terminal output:

1. **`prep-osac`** (Ansible) — clones osac-installer, copies the development overlay to a working overlay (`osac-devel`), writes secrets (license, pull secret, SSH keys), configures env files with Netris integration settings, and disables unused components (bmf-operator).

2. **`run-osac-setup`** (shell) — runs `setup.sh` directly in the terminal with live output. This installs OCP operators (LVMS, MetalLB, CNV, cert-manager, Authorino, Keycloak, AAP), deploys OSAC via Helm, applies AAP configuration, and runs post-install setup (AAP token, hub registration, tenant creation).

## Configuration

All parameters are in [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml). Override any variable via `EXTRA_VARS`:

```bash
make deploy-ocp EXTRA_VARS="ocp_version=4.21"
make deploy-osac EXTRA_VARS='{"osac_installer_branch": "feature-x"}'
```

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_version` | `4.21` | OpenShift version |
| `ocp_cluster_name` | `ocp-sno` | OCP cluster name |
| `ocp_base_domain` | `osac.local` | DNS base domain |
| `ocp_server_vcpu` | `20` | OCP VM vCPUs |
| `ocp_server_memory_gb` | `64` | OCP VM RAM (GB) |
| `ocp_subnet_cidr` | `192.168.40.0/24` | OCP VNet subnet |
| `ocp_dnat_ip` | `198.51.100.2` | DNAT IP for OCP API/apps access |
| `osac_namespace` | `osac-devel` | OSAC Kubernetes namespace |
| `osac_kustomize_overlay` | `osac-devel` | OSAC overlay (copied from development) |
| `osac_values_file` | `values/development/values.yaml` | Helm values file |
| `osac_installer_branch` | `main` | osac-installer branch |
| `netris_username` | `netris` | Netris API username |
| `netris_password` | `netris` | Netris API password |
| `ew_fabric_enable` | `0` | East-West fabric (0=NS only) |
| `caas_ocp_version` | `4.21` | OCP version for CaaS discovery ISO and release image |
| `caas_cluster_template` | `ocp_ci_small` | Cluster template for CaaS cluster creation |
| `caas_cluster_name` | `caas-ci-cluster` | CaaS cluster name |
| `caas_host_type_id` | `ci-worker` | Resource class for CaaS agents |

See [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml) for the full list.
