# Prerequisites

What your environment must satisfy before running
[`scripts/bootstrap-cloud.sh`](../scripts/bootstrap-cloud.sh).

---

## Infrastructure

| Component | Minimum | Notes |
|---|---|---|
| **Harvester HCI** | v1.7.x | Multi-node recommended for HA; single-node OK for dev. KubeOVN is the default CNI on v1.7+; the platform assumes it. |
| **Rancher** | v2.12.x | Provisioned by `modules/bootstrap`; the operator does NOT bring an existing Rancher. |
| **Storage** | Longhorn (Harvester default) | The platform expects a Longhorn StorageClass for PVCs. |
| **Container runtime** | RKE2 v1.33+ on the dcapi-controlplane cluster | Set by `modules/workloads/k8s-cluster` defaults. |

---

## Network

| Item | Detail |
|---|---|
| **VLAN-tagged bridge** | Management network reachable from the Harvester hosts; the bootstrap LB and dcapi-controlplane cluster live here. The TF modules configure VLAN tagging. |
| **IP pool** | A contiguous range of free IPs on the management VLAN (5–10 IPs minimum) for kube-vip LB allocations. Configured via `ippool_subnet` / `ippool_start` / `ippool_end` in `terraform.tfvars`. |
| **Wildcard DNS** | A wildcard `A` record (`*.cloud.example.com`) pointing at the cloud-ui ingress LB IP. The platform's public hostnames (cloud-ui, dc-api) derive from this. Single-host DNS records also work; wildcard is more convenient as new managed services are added. |
| **Outbound to GHCR** (Path A only) | The dcapi-controlplane cluster must be able to pull images from `ghcr.io`. Air-gapped sites use Path B and an internal registry instead. |
| **Outbound to the IdP** | `dc-api` reaches the OIDC issuer's `.well-known/openid-configuration` on startup. |

---

## Identity provider

The platform uses OIDC for all user authentication. Any provider that
implements **Authorization Code + PKCE** works. Tested with
[Asgardeo](https://wso2.com/asgardeo); others (Keycloak, Auth0, Okta)
follow the same setup.

Required from the IdP side:

- **Two applications**, both with PKCE enabled and no client secret on
  the public application (the cloud-ui BFF uses a confidential client;
  dcctl uses a public client):
  - `cloud-ui-bff` — confidential, redirect URI
    `https://<cloud-ui-host>/v1/auth/callback`
  - `dcctl` — public, redirect URI
    `http://localhost:<random-port>/callback`
- **An "admin" group**, plus a per-tenant group convention
  (e.g. `tenant-<slug>`). dc-api maps OIDC group claims to platform
  RBAC; see [docs/rbac.md](rbac.md) (added in a follow-up).
- The `groups` claim on the ID token MUST list the user's group
  memberships. Some IdPs require explicit opt-in to include groups in
  the token.

---

## Local tooling

The bootstrap wrapper runs on the operator's workstation, not on the
cluster. The wrapper needs:

| Tool | Version | Used for |
|---|---|---|
| `terraform` | ≥ 1.6 | All TF layers. |
| `kubectl` | matches Harvester K8s version | Validating connectivity. |
| `jq` | any | Parsing TF outputs in the wrapper. |
| `yq` | any | Reading `terraform.tfvars` lines. |
| `curl` | any | Probing the OIDC `.well-known` URL. |
| `helm` | ≥ 3 | Some layers install Helm charts. |
| Docker / Podman (Path B only) | any | Building images from source. |

The wrapper validates these before doing any work. If any are missing
it fails fast with `exit 2`.

---

## Permissions

The operator running the wrapper needs:

- A Harvester kubeconfig with cluster-admin (or equivalent rights to
  create namespaces, PVCs, VirtualMachines, NADs).
- An admin password for the Rancher server (set in `terraform.tfvars`).
- IdP admin access (to create the OIDC applications).
- Access to write to your image registry if you're following Path B.
