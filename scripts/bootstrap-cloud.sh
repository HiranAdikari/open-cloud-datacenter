#!/usr/bin/env bash
#
# bootstrap-cloud.sh — orchestrate the full sovereign-cloud install.
#
# What it does:
#   1. Validates prerequisites (kubectl reachable, jq/yq present, OIDC
#      issuer well-known URL resolvable, image registry pullable, …).
#   2. Runs each Terraform layer in order, waiting for each to be
#      Apply-clean before moving to the next.
#   3. Reports a summary at the end with the resulting URLs the
#      operator needs to hand to tenants (cloud-ui URL, dc-api URL,
#      OIDC redirect URI to set on the IdP).
#
# This script is a thin wrapper — every layer is a normal Terraform
# layer under examples/consumer/. Operators can run any single layer
# manually with `terraform apply` from that layer's directory if they
# prefer step-by-step bring-up; the wrapper just runs them in order
# without manual gating.
#
# Usage:
#   ./scripts/bootstrap-cloud.sh \
#       --consumer-dir   ../my-cloud-config      # where terraform.tfvars lives
#       [--layer-from    01-bootstrap]           # resume from a specific layer
#       [--skip-prereq]                          # skip the prerequisite checks
#       [--dry-run]                              # plan every layer, apply nothing
#
# Default behaviour: each layer plans then applies (terraform apply
# -auto-approve). Plans are printed inline so the log shows the diff
# for every layer.
#
# Partial / existing setups: do one --dry-run pass first to eyeball
# every layer's plan (layers you didn't touch should show
# "No changes"). Once you're happy with the diffs, re-run without
# --dry-run to apply.
#
# Exit codes:
#   0 success
#   2 prerequisite check failed
#   3 a layer's terraform apply failed
#   4 invalid arguments
#
# Re-runnable: each layer is idempotent. Re-running the script after a
# successful layer is a no-op for that layer.

set -euo pipefail

# ── arg parse ────────────────────────────────────────────────────────────────
consumer_dir=""
layer_from=""
skip_prereq=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer-dir) consumer_dir="$2"; shift 2 ;;
    --layer-from)   layer_from="$2"; shift 2 ;;
    --skip-prereq)  skip_prereq=true; shift ;;
    --dry-run)      dry_run=true; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -50
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 4
      ;;
  esac
done

if [[ -z "$consumer_dir" ]]; then
  echo "ERROR: --consumer-dir is required (the directory holding your terraform.tfvars)" >&2
  echo "       Copy examples/consumer/ to a private repo of your own and pass that path." >&2
  exit 4
fi

if [[ ! -d "$consumer_dir" ]]; then
  echo "ERROR: consumer-dir does not exist: $consumer_dir" >&2
  exit 4
fi

consumer_dir=$(cd "$consumer_dir" && pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# ── layer order ──────────────────────────────────────────────────────────────
# Each entry is a relative path inside the consumer dir. Add layers to this
# list as new modules land in the platform; the order is the dependency order
# (later layers depend on artefacts the earlier ones produce).
#
# Conventionally a consumer's directory tree mirrors examples/consumer/:
#   01-bootstrap/                     Rancher server + Harvester registration
#   02-management/                    Networks, storage, RBAC scaffolding
#   03-identity/                      OIDC apps on the IdP
#   04-dc-controlplane/               The dcapi-controlplane RKE2 cluster
#   05-dc-controlplane-services/      dc-api + cloud-ui + operators on the cluster
#   06-tenant-spaces/                 (optional) per-tenant pre-provisioned namespaces
layers=(
  "01-bootstrap"
  "02-management"
  "03-identity"
  "04-dc-controlplane"
  "05-dc-controlplane-services"
)

# ── prereq checks ────────────────────────────────────────────────────────────
check_prereqs() {
  local fail=0
  for cmd in terraform kubectl jq yq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "  ✗ missing required tool: $cmd"
      fail=1
    else
      echo "  ✓ $cmd"
    fi
  done

  if [[ ! -f "$consumer_dir/terraform.tfvars" ]]; then
    echo "  ✗ $consumer_dir/terraform.tfvars not found — copy examples/consumer/terraform.tfvars.example and fill it in"
    fail=1
  else
    echo "  ✓ terraform.tfvars present"
  fi

  for required_var in harvester_kubeconfig_path oidc_issuer_url rancher_hostname; do
    if ! grep -qE "^\s*${required_var}\s*=" "$consumer_dir/terraform.tfvars" 2>/dev/null; then
      echo "  ✗ terraform.tfvars missing required: ${required_var}"
      fail=1
    fi
  done

  oidc_url=$(grep -E "^\s*oidc_issuer_url\s*=" "$consumer_dir/terraform.tfvars" 2>/dev/null \
    | head -1 | sed -E 's/^[^"]*"([^"]+)".*/\1/')
  if [[ -n "$oidc_url" ]]; then
    if curl -fsS --max-time 5 "${oidc_url%/}/.well-known/openid-configuration" >/dev/null 2>&1; then
      echo "  ✓ OIDC issuer well-known URL reachable: $oidc_url"
    else
      echo "  ✗ OIDC issuer well-known URL NOT reachable: ${oidc_url%/}/.well-known/openid-configuration"
      fail=1
    fi
  fi

  return $fail
}

if ! $skip_prereq; then
  echo "── Prerequisite checks ────────────────────────────────────"
  if ! check_prereqs; then
    echo "Prerequisite check failed. Fix the issues above and re-run." >&2
    echo "(Use --skip-prereq if you've validated externally and want to proceed.)" >&2
    exit 2
  fi
  echo
fi

# ── layer runner ─────────────────────────────────────────────────────────────
run_layer() {
  local layer="$1"
  local layer_dir="$consumer_dir/$layer"

  if [[ ! -d "$layer_dir" ]]; then
    echo "SKIP $layer (directory not present in consumer dir)"
    return 0
  fi

  echo
  echo "── Layer: $layer ──────────────────────────────────────────"
  pushd "$layer_dir" >/dev/null

  terraform init -input=false >/dev/null
  terraform fmt -check >/dev/null || terraform fmt >/dev/null
  terraform validate >/dev/null

  if $dry_run; then
    terraform plan -input=false -compact-warnings
    popd >/dev/null
    echo "✓ $layer planned (dry-run, no apply)"
    return 0
  fi

  terraform plan -input=false -compact-warnings -out=tfplan.out
  terraform apply -input=false -auto-approve tfplan.out
  rm -f tfplan.out

  popd >/dev/null
  echo "✓ $layer done"
}

# ── main ─────────────────────────────────────────────────────────────────────
start_idx=0
if [[ -n "$layer_from" ]]; then
  for i in "${!layers[@]}"; do
    if [[ "${layers[$i]}" == "$layer_from" ]]; then
      start_idx=$i
      break
    fi
  done
  echo "Resuming from layer: $layer_from (index $start_idx)"
fi

for ((i=start_idx; i<${#layers[@]}; i++)); do
  run_layer "${layers[$i]}"
done

# ── summary ──────────────────────────────────────────────────────────────────
echo
echo "── Summary ────────────────────────────────────────────────"
echo "Consumer dir: $consumer_dir"
echo
echo "Cloud-UI URL  : (terraform output -raw cloud_ui_url from layer 05)"
echo "DC-API URL    : (terraform output -raw dc_api_url from layer 05)"
echo "OIDC callback : (terraform output -raw oidc_redirect_uri from layer 03)"
echo "                ↑ register this on your IdP if the IdP module did not"
echo "                  do it automatically."
echo
echo "Next steps:"
echo "  - Confirm the UI loads at the cloud-ui URL"
echo "  - dcctl login (set the API URL via DCCTL_API_URL or ~/.dcctl/config.yaml)"
echo "  - Register your first tenant: 'dcctl admin tenant create --slug ...'"
echo "  - Hand the cloud-ui URL to your tenant owners"
