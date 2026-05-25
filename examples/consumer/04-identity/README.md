# 04-identity

Creates the **Rancher SSO** OIDC application on your IdP and wires
Rancher to use it. Two module calls:

- [`modules/identity/providers/asgardeo`](../../../modules/identity/providers/asgardeo/) — registers the app + returns client_id/secret + endpoints.
- [`modules/identity/rancher-oidc`](../../../modules/identity/rancher-oidc/) — feeds those into Rancher's generic-OIDC auth provider.

**Reads from terraform.tfvars:** `asgardeo_org_name`,
`asgardeo_management_client_id`, `asgardeo_management_client_secret`,
`asgardeo_app_name`, `skip_consent`.

**Reads from upstream layers:** `01-bootstrap` (rancher_url),
`02-rancher-auth` (admin_token).

**Outputs:** `oidc_issuer_url`, `oidc_discovery_url`,
`rancher_oidc_client_id`.

**Readiness gate (wrapper):** curls `<oidc_issuer_url>/.well-known/openid-configuration`.

## What this layer does NOT do

- It does not create the dc-api BFF (`cloud-ui-bff`) or dcctl OIDC clients.
  Those are dc-api-specific and OCD does not (yet) ship a module for them.
  Create them on your IdP manually per
  [`../../../docs/prerequisites.md`](../../../docs/prerequisites.md) and
  plug `bff_client_id` / `bff_client_secret` / `dcctl_client_id` into
  `terraform.tfvars`. Layer 06 reads them from there.

## Non-Asgardeo IdPs

Swap the `module "idp"` call to `modules/identity/providers/azure-ad`
(also ships in OCD) or write your own provider preset module that
exports the same outputs (`client_id`, `client_secret`, `issuer_url`,
`auth_endpoint`, `token_endpoint`, `jwks_url`, `discovery_url`). The
`module "rancher_oidc"` call is generic and works against any provider
that emits those outputs.

Apply time: seconds.
