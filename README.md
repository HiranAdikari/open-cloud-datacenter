# Open Cloud Data Center

The Open Cloud Data Center initiative provides a standardized, scalable,
and customizable sovereign-cloud platform that runs on
[Harvester HCI](https://harvesterhci.io/) + [Rancher](https://rancher.com/).
It packages everything a team needs to bring up an Azure-/AWS-style cloud
control plane on their own hardware: infrastructure modules, a REST API
+ CLI + web UI for tenants, a set of operators for managed services, and
the reference wiring that ties them together.

## Why choose Open Cloud Data Center?

- **Sovereignty** — complete control over data and infrastructure.
- **Portability** — move workloads across cloud providers or on-premises hardware.
- **Cost-efficiency** — optimise resource usage; no vendor lock-in.
- **Open & extensible** — built on open standards; managed-service operators
  follow a documented contract so additional services plug in cleanly.

---

## What's in this repo

| Path | Purpose |
|---|---|
| `modules/` | Terraform modules — the infrastructure layer. Bootstrap a Rancher server, register Harvester, deploy management networks/storage/RBAC, provision tenant RKE2 clusters. |
| `dc-api/` | The REST API server (Go). Tenants and CLIs talk only to this. Owns state in Postgres; provisions VMs via Harvester, clusters via Rancher, secrets via the keyvault operator, etc. |
| `cloud-ui/` | The web UI (React + TypeScript + Fluent UI). Consumes the dc-api OpenAPI spec; ships as a Docker image alongside dc-api. |
| `dcctl/` | The CLI (Go, Cobra). `dcctl vm create`, `dcctl cluster create`, etc. Talks to dc-api over OIDC + PKCE. |
| `crds/` | Kubernetes operators for managed services (e.g. `crds/keyvault/`). Each operator is a separately-buildable module that conforms to the [Managed Services Integration Contract](docs/managed-services-integration.md). |
| `docs/` | Architecture, contracts, runbooks, installation. Start with [docs/install.md](docs/install.md). |
| `scripts/` | Bootstrap + dev helpers. `scripts/bootstrap-cloud.sh` is the thin orchestration wrapper for a fresh install. |

---

## Quick start

### Path A — use the canonical images (~15 min once prerequisites are met)

The standard install path. Uses images this repo's CI publishes to
`ghcr.io/wso2/*` at each tagged release.

1. Read [docs/prerequisites.md](docs/prerequisites.md) — you need Harvester ≥ 1.7.x,
   Rancher v2.12.x, an OIDC IdP supporting Auth Code + PKCE, and a wildcard DNS
   record + ingress LB IP.
2. Copy [`examples/consumer/`](examples/consumer/) (added in a follow-up) to a private
   config repo of your own.
3. Edit your `terraform.tfvars` with hostnames, secrets references, capacity caps.
4. `./scripts/bootstrap-cloud.sh` — see [docs/install.md](docs/install.md) for what it does.

### Path B — build your own images (supply-chain control / customisation)

For consumers who need to build from source — air-gapped sites, organisations
that require signed images from their own registry, or anyone modifying the
platform:

1. Clone this repo at a tagged ref.
2. `make image` in each component dir (`dc-api/`, `cloud-ui/`, `dcctl/`, `crds/*/`).
3. Push images to your own registry.
4. In your consumer's `terraform.tfvars`, override the image variables
   (`dc_api_image`, `cloud_ui_image`, `keyvault_operator_image`, …).
5. Run `./scripts/bootstrap-cloud.sh` as in Path A — same TF modules consume
   whichever images you pointed at.

Customisation needs that should NOT require a source fork: branding, OIDC
issuer, hostnames, capacity caps, feature flags. All env-var driven. Reach
for a source fork only when env vars + the operator framework's extension
points don't suffice.

---

## Modules

Reusable Terraform modules under `modules/`. See [docs/architecture.md](docs/architecture.md)
for how they relate.

### Bootstrap

| Module | Description |
|--------|-------------|
| [modules/bootstrap](modules/bootstrap/README.md) | Provisions an RKE2-based Rancher server on Harvester HCI via cloud-init, with a Load Balancer and IP pool for external access. |

### Identity

| Module | Description |
|--------|-------------|
| [modules/identity/rancher-oidc](modules/identity/rancher-oidc/README.md) | Configures Rancher to use a generic OIDC provider for user authentication. |
| [modules/identity/providers/asgardeo](modules/identity/providers/asgardeo/README.md) | Presets for integrating WSO2 Asgardeo as the identity provider. |

### Management

| Module | Description |
|--------|-------------|
| [modules/management/networking](modules/management/networking/README.md) | Creates and manages VLAN-backed Harvester networks for tenant and management workloads. |
| [modules/management/storage](modules/management/storage/README.md) | Downloads and registers OS images into Harvester HCI, making them available for VM provisioning. |
| [modules/management/cluster-roles](modules/management/cluster-roles/README.md) | Defines custom Rancher role templates (e.g. `vm-metrics-observer`) shared across tenant projects. |
| [modules/management/tenant-space](modules/management/tenant-space/README.md) | Full team onboarding: creates a Rancher project, namespace, resource quotas, and role bindings. |
| [modules/management/rbac](modules/management/rbac/README.md) | Lightweight module for bulk creating projects and namespaces without advanced role bindings. |
| [modules/management/harvester-integration](modules/management/harvester-integration/README.md) | Registers the Harvester HCI cluster into Rancher, enabling the UI extension and cloud credential. |
| [modules/management/dc-controlplane](modules/management/dc-controlplane/) | Provisions the `dcapi-controlplane` RKE2 cluster that hosts dc-api / cloud-ui / managed-service operators. Bundles kube-vip + dual-NIC + IP pool wiring. |
| [modules/management/dc-controlplane-services](modules/management/dc-controlplane-services/) | Deploys dc-api + cloud-ui + Postgres onto the dcapi-controlplane cluster; wires the OIDC client IDs + secrets. |
| [modules/management/dc-webhook](modules/management/dc-webhook/README.md) | Admission webhook supporting dc-api's tenant-isolation guarantees. |
| [modules/management/namespace-credential-provisioner](modules/management/namespace-credential-provisioner/README.md) | Reconciler that mints per-namespace credentials for tenant workloads. |

### Monitoring

| Module | Description |
|--------|-------------|
| [modules/monitoring](modules/monitoring/README.md) | Deploys a full monitoring stack (Prometheus / Alertmanager / Calert) with Google Chat notification support. |

### Workloads

| Module | Description |
|--------|-------------|
| [modules/workloads/k8s-cluster](modules/workloads/k8s-cluster/README.md) | Provisions a tenant RKE2 cluster as a VM set on Harvester via Rancher. |
| [modules/workloads/vm](modules/workloads/vm/README.md) | Provisions standalone virtual machines on Harvester HCI with support for multiple disks and cloud-init. |
| [modules/workloads/harvester-cloud-credential](modules/workloads/harvester-cloud-credential/) | Creates the Harvester cloud credential in Rancher that downstream workload modules use. |
| [modules/workloads/harvester-vm-access](modules/workloads/harvester-vm-access/) | RBAC bindings letting Rancher project members reach Harvester VM consoles + VNCs. |

---

## Documentation

- [docs/install.md](docs/install.md) — end-to-end installation runbook.
- [docs/prerequisites.md](docs/prerequisites.md) — what your environment must
  satisfy before installation.
- [docs/architecture.md](docs/architecture.md) — infrastructure architecture
  (the TF-modules view).
- [docs/dc-api-architecture.md](docs/dc-api-architecture.md) — the platform
  layer architecture (dc-api / cloud-ui / dcctl / operators).
- [docs/managed-services-integration.md](docs/managed-services-integration.md) —
  contract for teams building new managed-service operators.
- [docs/managed-services-framework.md](docs/managed-services-framework.md) —
  internal framework design for wiring operators into dc-api.

---

## Contributing

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) and
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

Apache-2.0 — see [LICENSE](LICENSE).
