# examples/consumer

Reference consumer template for a fresh Open Cloud Data Center install.
**Copy this directory to a private repo of your own** (it's a template, not
something you edit in-place inside OCD), edit `terraform.tfvars` with your
environment-specific values, and run
[`../../scripts/bootstrap-cloud.sh`](../../scripts/bootstrap-cloud.sh) to
provision the platform.

## What's in here

```
01-bootstrap/                  → Rancher install on Harvester
02-rancher-auth/               → permanent admin password + API token
03-management/                 → register Harvester into Rancher; networks; storage; RBAC
04-identity/                   → OIDC provider + Rancher SSO wiring
05-dc-controlplane/            → the dcapi-controlplane RKE2 cluster
06-dc-controlplane-services/   → dc-api + cloud-ui Deployment on the cluster
07-dc-operators/               → keyvault operator, dc-webhook, …
terraform.tfvars.example       → root template — copy to terraform.tfvars and fill
```

Each layer is a standalone Terraform layer. Each layer's `main.tf` calls one
or more OCD modules pinned via `locals.ocd_ref` (default: `v0.8.2`). To
upgrade OCD, bump the `ocd_ref` in every layer's `main.tf` AND re-apply.

## Quick start

```bash
# 1. Copy this template to your own private repo:
cp -r examples/consumer ../my-cloud-config

# 2. Fill in your values:
cp ../my-cloud-config/terraform.tfvars.example ../my-cloud-config/terraform.tfvars
$EDITOR ../my-cloud-config/terraform.tfvars

# 3. From the OCD repo root, run the wrapper:
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config --dry-run
# … review plans for every layer …
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config
# or, layer-by-layer:
./scripts/bootstrap-cloud.sh --consumer-dir ../my-cloud-config --one-at-a-time
```

See [`../../docs/install.md`](../../docs/install.md) for the full runbook
and [`../../docs/prerequisites.md`](../../docs/prerequisites.md) for what
your environment must satisfy beforehand.

## State backend

Each layer defaults to **local state** — a `terraform.tfstate` file is
written next to `main.tf` and listed in `.gitignore`. Fine for a first
install or solo dev.

For production / multi-operator setups, uncomment + edit the `backend "s3"`
block in each layer's `versions.tf`. Pattern is consistent across layers:
the bucket is the same, only `key` differs (e.g.
`<env>/01-bootstrap/terraform.tfstate`,
`<env>/02-rancher-auth/terraform.tfstate`, …). Pre-create the S3 bucket
and the DynamoDB lock table out of band.

## Testing against an existing (already-applied) setup

If you're using this template to inspect what would change against an
existing install (e.g. one previously provisioned with a private consumer
repo), point each layer's S3 backend at the **same bucket + same keys**
the original consumer used, then run with `--dry-run`. Layers you haven't
touched should show `No changes`; any non-zero diff is a signal that
something has drifted or that this template is wired differently from
the original.

## IdP setup is partly manual

Layer 04-identity creates one OIDC application for Rancher's UI SSO (via
`modules/identity/providers/asgardeo` + `modules/identity/rancher-oidc`).
**The dc-api BFF + dcctl OIDC clients are not auto-created** — OCD does
not ship an IdP-app-creator module for those yet. Create them on your
IdP manually per
[`../../docs/prerequisites.md`](../../docs/prerequisites.md) and plug
their client IDs + secrets into `terraform.tfvars`. Layer 06 reads them
from there.

## Adapting to a non-Asgardeo IdP

Swap the `modules/identity/providers/asgardeo` call in
`04-identity/main.tf` for `modules/identity/providers/azure-ad` (also
ships in OCD) or your own provider preset. `modules/identity/rancher-oidc`
is generic and consumes whatever client/secret/issuer/endpoints the
provider preset exports.
