# Installation runbook

End-to-end runbook for bringing up a fresh sovereign-cloud installation on
your own Harvester + Rancher infrastructure. Targets the **consumer**
audience: an operator preparing to deploy the platform for a tenant
organisation.

Read [prerequisites](prerequisites.md) first.

---

## 0. Choose a path

| Path | Use when |
|---|---|
| **A. Canonical images** | First install; trying the platform; happy to consume `ghcr.io/wso2/*` images at a pinned tag. |
| **B. Build from source** | Air-gapped site, must build from source for compliance/supply-chain reasons, or customising the platform beyond what env vars expose. |

Both paths use the same TF modules and the same wrapper script. They only
differ in which image registry the deployment pulls from.

---

## 1. Set up your consumer config repo

The platform's source lives here (this repo). Your *consumer-specific*
configuration lives in a separate private repo that **you** maintain.
It holds your hostnames, secrets references, capacity caps, and any
overrides — never any source modules.

A `examples/consumer/` template will land in a follow-up PR; until then,
mirror the structure of the WSO2 reference consumer (see the architecture
note in [architecture.md](architecture.md) §3). The expected layout:

```
my-cloud-config/
├── terraform.tfvars              # global vars: hostnames, OIDC, secrets refs
├── dependencies.yaml             # pins OCD ref the layers consume from
├── 01-bootstrap/                 # Rancher install on Harvester
├── 02-rancher-auth/              # Rancher admin token
├── 03-management/                # Harvester registration, networks, storage, RBAC
├── 04-identity/                  # OIDC applications on the IdP
├── 05-dc-controlplane/           # provisions the dcapi-controlplane RKE2 cluster
├── 06-dc-controlplane-services/  # deploys dc-api + cloud-ui on it
└── 07-dc-operators/              # keyvault operator + future managed-service operators
```

Each layer is a normal Terraform layer. Each consumes the same root
`terraform.tfvars` and shares state via `*.tfstate` files in its directory.

---

## 2. Fill in `terraform.tfvars`

Minimum required variables (the wrapper's prereq check will fail loudly if
any are missing):

```hcl
# Harvester
harvester_kubeconfig_path = "/path/to/harvester-kubeconfig.yaml"

# Rancher
rancher_hostname        = "rancher.cloud.example.com"
rancher_admin_password  = "..."     # initial admin pw; rotate after install

# OIDC IdP (must support Authorization Code + PKCE)
oidc_issuer_url         = "https://idp.example.com/oauth2/realm"
oidc_admin_group        = "platform-admins"
oidc_tenant_group_prefix = "tenant-"

# Network
ippool_subnet           = "192.168.50.0/24"
ippool_gateway          = "192.168.50.1"
ippool_start            = "192.168.50.10"
ippool_end              = "192.168.50.50"

# Image registry (Path A) — defaults work out of the box
dc_api_image            = "ghcr.io/wso2/dc-api:v0.9.0"
cloud_ui_image          = "ghcr.io/wso2/cloud-ui:v0.9.0"
keyvault_operator_image = "ghcr.io/wso2/keyvault-operator:v0.9.0"
```

Path B users substitute their own registry for the `*_image` vars.

---

## 3. Run the bootstrap wrapper

```bash
cd /path/to/this/repo                            # this repo (open-cloud-datacenter)
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config
```

The wrapper:

1. Validates prerequisites (`terraform`, `kubectl`, `jq`, `yq`, `curl`
   present; `terraform.tfvars` complete; OIDC well-known URL reachable).
2. Runs each Terraform layer in dependency order. Every layer plans
   then applies (`terraform apply -auto-approve`); the plan output for
   every layer is printed inline so the log shows the full diff. After
   each apply the wrapper runs a per-layer readiness check (e.g. poll
   Rancher `/v3/ping` after `01-bootstrap`, `kubectl wait` all nodes
   Ready after `05-dc-controlplane`, `GET /healthz` on dc-api after
   `06-dc-controlplane-services`) before starting the next layer. This
   prevents "apply done" from racing the actual service coming up.

   Layers:
   - **01-bootstrap** — provisions an RKE2 VM on Harvester, installs
     Rancher into it, sets up the management LB IP pool.
   - **02-rancher-auth** — bootstraps the Rancher admin password and
     issues an API token consumed by every downstream layer.
   - **03-management** — registers Harvester into Rancher; creates
     management networks, image catalogue, RBAC scaffolding.
   - **04-identity** — creates OIDC applications (one for dc-api,
     one for cloud-ui's BFF, one for dcctl) on the IdP.
   - **05-dc-controlplane** — provisions a second RKE2 cluster (the
     `dcapi-controlplane` cluster) that will host dc-api / cloud-ui
     / managed-service operators.
   - **06-dc-controlplane-services** — deploys dc-api + cloud-ui
     Deployments + Services + Ingress on the dcapi-controlplane
     cluster; creates the dc-api Postgres; wires the IdP client IDs
     + secrets via a Kubernetes Secret.
   - **07-dc-operators** — installs the keyvault operator (and future
     per-service operators) onto the dcapi-controlplane cluster.
3. Prints a summary with the URLs the operator hands to tenant owners.

### One layer at a time — for manual cutovers

For production cutovers where the operator wants to inspect cluster
state between layers (verify Rancher's UI loads, that dcapi-cluster
nodes look healthy in Rancher, etc.):

```bash
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config --one-at-a-time
```

The wrapper runs just the first layer (`01-bootstrap`), runs the
readiness gate, then exits with the resume command for the next
layer. Run it again to continue.

### Partial / existing setups — eyeball plans first

On an environment where some layers are already applied (e.g. you
destroyed `05-dc-controlplane` + `06-dc-controlplane-services` to
re-test bring-up but `01-bootstrap` / `02-rancher-auth` /
`03-management` / `04-identity` should be untouched), do a `--dry-run`
pass first so you can read every layer's plan without anything being
applied:

```bash
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config --dry-run
```

For each untouched layer the plan must show **`No changes`** — if
any of them show a non-zero diff, that's a signal that either the
import is wrong, a variable drifted, or some out-of-band manual
edit happened. Fix the divergence before re-running without
`--dry-run`.

Once the dry-run looks right, run without `--dry-run` to apply.

End-to-end time: **~25–40 min** on a healthy Harvester cluster. The two
slow steps are the Rancher install (~10 min) and the
dcapi-controlplane cluster bring-up (~10 min) — both bounded by RKE2
bring-up latency.

### Re-run / resume

The wrapper is idempotent: every layer's `terraform apply` is a no-op
when nothing changed. To resume after a transient failure on a specific
layer:

```bash
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config --layer-from 05-dc-controlplane
```

---

## 4. Verify the install

Once the wrapper reports success:

1. **Cloud UI** — open the URL from the summary (e.g.
   `https://cloud.example.com`). You should see the OIDC login screen.
2. **Log in as a platform admin** — must be a member of the OIDC group
   named in `oidc_admin_group`.
3. **Tenant picker** — the UI lands on `/tenants`; an admin sees a
   "Register tenant" option there.
4. **Register a tenant** via the UI OR via `dcctl admin tenant create`:
   ```bash
   dcctl admin tenant create \
       --slug example-co --display-name "Example Co" \
       --cpu-cap 40 --memory-cap 128 --storage-cap 1000
   ```
5. **Add a member to the tenant** — first via UI, or via:
   ```bash
   dcctl tenant add-member --user-id <oidc-sub> --role owner
   ```
6. **Smoke test** — log in as that tenant user, create a project, then
   a VM. If the VM reaches ACTIVE, the platform is healthy end-to-end.

---

## 5. Operating beyond bootstrap

- **Upgrade**: bump `dependencies.yaml` to a new OCD ref, then re-run
  the wrapper. Each layer's `terraform apply` rolls out only the diff.
- **Add a new managed service** (cache, database, etc.): the operator
  ships as a `crds/<service>/` module here; consumers reference it via
  a new module call in their `07-dc-operators/` layer, plus a per-service
  registration in `06-dc-controlplane-services/` if dc-api needs to be
  rebuilt with new provider wiring.
- **Backup / restore**: see [runbooks/](runbooks/) for the dc-api
  Postgres + Rancher etcd backup procedures.
- **Audit + observability**: dc-api ships structured JSON logs at
  stdout; cloud-ui ships access logs at the ingress; both export
  Prometheus metrics at `/metrics`.

---

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| Bootstrap layer hangs at "Rancher install" | Wrong `rancher_hostname` (must resolve to the LB IP from `ippool_*`) | DNS; `kubectl -n cattle-system get pods` on the bootstrap cluster |
| `dc-api` CrashLoopBackoff at first start | Postgres URL/credentials wrong in the secret, or migrations failed | `kubectl -n dcapi logs deploy/dc-api -c dc-api` |
| Cloud-UI login redirects to `/login` immediately after callback | OIDC client ID / redirect URI mismatch on the IdP | layer 03's outputs vs the IdP's app config |
| Operator-created CRDs missing | Layer 05 didn't apply the CRDs (`kubectl get crd` returns nothing for `keyvault.opencloud.wso2.com`) | `kubectl apply` the `crds/<svc>/config/crd/bases/*.yaml` manually; raise a bug |

For deeper issues see [runbooks/rke2-recovery.md](runbooks/rke2-recovery.md)
and the per-component troubleshooting in the relevant `crds/<svc>/USAGE.md`
or `dc-api/internal/*/README.md`.
