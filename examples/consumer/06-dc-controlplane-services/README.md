# 06-dc-controlplane-services

Deploys **dc-api + cloud-ui** (and Postgres, ingress, secrets) on the
dcapi-controlplane cluster created by layer 05. Calls
[`modules/management/dc-controlplane-services`](../../../modules/management/dc-controlplane-services/).

**Reads from terraform.tfvars:** `harvester_kubeconfig_path`,
`dc_api_image`, `cloud_ui_image`, `dcapi_hostname`, `cloud_ui_hostname`,
`tenant_group_prefix`, `admin_group`, `log_level`, `operator_ssh_key`,
`operator_password`, `ghcr_username`/`pat`, BFF + dcctl client IDs +
secrets, ARC settings, VPC external settings.

**Reads from upstream layers:** `01-bootstrap` (rancher_url),
`02-rancher-auth` (admin_token), `03-management`
(harvester_cloud_credential_id), `04-identity` (oidc_issuer_url,
rancher_oidc_client_id), `05-dc-controlplane` (dcapi_cluster_v3_id).

**Outputs:** `dc_api_url`, `cloud_ui_url`, `postgres_password` (sensitive).

**Readiness gate (wrapper):** curls `<dc_api_url>/healthz` until 200.

Apply time: 5–10 minutes (Helm installs, Deployments roll, ingress + cert
ready).
