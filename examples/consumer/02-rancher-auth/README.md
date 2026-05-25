# 02-rancher-auth

Sets the permanent Rancher admin password and emits the API token every
downstream layer consumes. Uses the `rancher2_bootstrap` resource directly
(no module wrapping needed).

**Reads from terraform.tfvars:** `bootstrap_password`, `rancher_admin_password`.

**Reads from upstream layer:** `01-bootstrap` → `rancher_url`.

**Outputs:** `admin_token` (sensitive).

**Readiness gate (wrapper):** authenticated probe `GET /v3/users?limit=1`
with the freshly-issued token.

Apply time: seconds.
