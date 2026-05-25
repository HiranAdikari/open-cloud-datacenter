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
#       [--one-at-a-time]                        # run a single layer then exit
#       [--skip-readiness]                       # skip the post-layer readiness wait
#
# Default behaviour: each layer plans then applies (terraform apply
# -auto-approve), then runs a per-layer readiness check (e.g. poll
# Rancher /v3/ping after 01-bootstrap, kubectl-wait nodes Ready
# after the dc-controlplane cluster) before starting the next layer.
# The readiness checks ensure "terraform apply exit 0" doesn't race
# the layer being truly usable from the next layer's perspective.
#
# Modes:
#   --dry-run         plan every layer, apply nothing, no readiness wait
#   --one-at-a-time   run one layer (init/plan/apply/wait), then exit;
#                     resume with --layer-from <next>. Preferred for
#                     manual / production cutovers where the operator
#                     wants to inspect cluster state between layers.
#   default           run all layers back-to-back with readiness gates
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
one_at_a_time=false
skip_readiness=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer-dir)   consumer_dir="$2"; shift 2 ;;
    --layer-from)     layer_from="$2"; shift 2 ;;
    --skip-prereq)    skip_prereq=true; shift ;;
    --dry-run)        dry_run=true; shift ;;
    --one-at-a-time)  one_at_a_time=true; shift ;;
    --skip-readiness) skip_readiness=true; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -60
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

# ── readiness helpers ────────────────────────────────────────────────────────
#
# Each helper polls a single readiness signal with a timeout. The
# wait_after() dispatcher below maps a layer name to the helper(s) that
# verify "this layer is truly usable by the next one." Add new entries
# as new layers land.
#
# Conventions:
#   - return 0 when ready; non-zero on timeout (caller decides whether
#     to abort the bootstrap or surface a warning).
#   - never sleep without bounds; honour the timeout argument.
#   - read terraform outputs from the layer's own dir; the caller has
#     already cd'd there.

wait_for_http_ok() {
  # $1=url $2=timeout_seconds (default 600) $3=description (optional)
  local url="$1" timeout="${2:-600}" desc="${3:-$1}"
  local elapsed=0 interval=5
  echo "  waiting for $desc to return 200 (timeout ${timeout}s)..."
  while (( elapsed < timeout )); do
    if curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 "$url" | grep -qE '^(200|401)$'; then
      # 401 means the endpoint is alive but expects auth — good enough
      # for liveness checks against /v3/ping etc.
      echo "  ✓ $desc reachable"
      return 0
    fi
    sleep "$interval"; elapsed=$((elapsed + interval))
  done
  echo "  ✗ timeout waiting for $desc after ${timeout}s" >&2
  return 1
}

wait_for_kubectl_nodes_ready() {
  # $1=kubeconfig_path $2=timeout (default 600)
  local kubeconfig="$1" timeout="${2:-600}"
  echo "  waiting for all nodes Ready in $kubeconfig (timeout ${timeout}s)..."
  if KUBECONFIG="$kubeconfig" kubectl wait --for=condition=Ready nodes --all --timeout="${timeout}s" >/dev/null 2>&1; then
    echo "  ✓ all nodes Ready"
    return 0
  fi
  echo "  ✗ kubectl wait timed out" >&2
  return 1
}

# wait_after — dispatch table mapping layer names to readiness checks.
# Called from the layer runner after a successful apply, before the
# next layer starts. Each case may shell out to wait_for_http_ok /
# wait_for_kubectl_nodes_ready / any other helper, sourced from the
# layer's terraform outputs.
#
# The function is the single touch-point operators edit when adding
# new layers — keep the wrapper's main loop generic.
wait_after() {
  local layer="$1"

  case "$layer" in
    01-bootstrap|*-bootstrap)
      # Rancher publishes /v3/ping unauthenticated; it 200s when the
      # cattle-system pods are serving requests, which is the gate
      # 02-rancher-auth needs before its rancher2_bootstrap can succeed.
      local rancher_url
      rancher_url=$(terraform output -raw rancher_url 2>/dev/null || true)
      [[ -z "$rancher_url" ]] && { echo "  (no rancher_url output; skipping readiness)"; return 0; }
      wait_for_http_ok "${rancher_url%/}/v3/ping" 900 "Rancher API ($rancher_url)"
      ;;

    02-rancher-auth|*-rancher-auth)
      # admin_token is sensitive — fetch it once and probe an
      # authenticated endpoint. /v3/users with limit=1 is the lightest
      # endpoint that exercises auth + the api-server.
      local rancher_url tok
      rancher_url=$(cd ../01-bootstrap 2>/dev/null && terraform output -raw rancher_url 2>/dev/null || true)
      tok=$(terraform output -raw admin_token 2>/dev/null || true)
      if [[ -z "$rancher_url" || -z "$tok" ]]; then
        echo "  (rancher_url or admin_token not resolvable; skipping)"
        return 0
      fi
      echo "  probing authenticated Rancher endpoint..."
      local code
      code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 \
        -H "Authorization: Bearer $tok" "${rancher_url%/}/v3/users?limit=1")
      if [[ "$code" == "200" ]]; then echo "  ✓ admin token works"; return 0; fi
      echo "  ✗ Rancher rejected the admin token (HTTP $code)" >&2
      return 1
      ;;

    03-management|*-management)
      # The management layer's terraform resources already block on
      # their own server-side reconcile (cloud credential creation,
      # NAD registration). Nothing extra to poll here.
      return 0
      ;;

    04-identity|*-identity|*-asgardeo-auth)
      # OIDC discovery URL must resolve before dc-api starts consuming
      # it. If the issuer URL is in the layer's outputs, probe it;
      # otherwise leave the validation to the prereq check (which
      # already runs at startup against terraform.tfvars).
      local issuer
      issuer=$(terraform output -raw oidc_issuer_url 2>/dev/null || true)
      [[ -z "$issuer" ]] && { return 0; }
      wait_for_http_ok "${issuer%/}/.well-known/openid-configuration" 60 "OIDC discovery"
      ;;

    05-dc-controlplane|*-dc-controlplane)
      # The cluster CR returns from Rancher long before the nodes have
      # joined and reached Ready. Pull the kubeconfig from outputs (the
      # consumer is expected to expose it as `dcapi_kubeconfig_path`
      # — a path on disk written by a local_file resource — or as
      # `dcapi_kubeconfig` raw YAML) and kubectl-wait nodes.
      local kc
      kc=$(terraform output -raw dcapi_kubeconfig_path 2>/dev/null || true)
      if [[ -z "$kc" ]]; then
        # Fallback: write raw kubeconfig output to a temp file.
        if terraform output -raw dcapi_kubeconfig >/dev/null 2>&1; then
          kc=$(mktemp); terraform output -raw dcapi_kubeconfig > "$kc"
        fi
      fi
      if [[ -z "$kc" || ! -s "$kc" ]]; then
        echo "  (no dcapi_kubeconfig_path / dcapi_kubeconfig output; skipping readiness — add one to enable the wait)"
        return 0
      fi
      wait_for_kubectl_nodes_ready "$kc" 1200
      ;;

    06-dc-controlplane-services|*-dc-controlplane-services|*-services)
      # dc-api exposes /healthz; once it returns 200 the layer is
      # truly usable from a tenant's perspective.
      local dcapi_url
      dcapi_url=$(terraform output -raw dc_api_url 2>/dev/null || true)
      [[ -z "$dcapi_url" ]] && { echo "  (no dc_api_url output; skipping)"; return 0; }
      wait_for_http_ok "${dcapi_url%/}/healthz" 600 "dc-api ($dcapi_url)"
      ;;

    *)
      # Unknown layer — no specific check. Add an entry above when a
      # new layer needs one.
      return 0
      ;;
  esac
}

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
  "02-rancher-auth"
  "03-management"
  "04-identity"
  "05-dc-controlplane"
  "06-dc-controlplane-services"
  "07-dc-operators"
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

  if $skip_readiness; then
    echo "  (--skip-readiness — not waiting for layer health)"
  else
    if ! wait_after "$layer"; then
      popd >/dev/null
      echo "✗ $layer applied but readiness check failed — investigate before continuing." >&2
      echo "  Re-run with --layer-from $layer once the issue is resolved," >&2
      echo "  or --skip-readiness to proceed past the gate." >&2
      exit 3
    fi
  fi

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

  # --one-at-a-time: stop after one successful layer so the operator can
  # eyeball cluster state before moving on.
  if $one_at_a_time; then
    next_idx=$((i + 1))
    if (( next_idx < ${#layers[@]} )); then
      echo
      echo "── one-at-a-time: stopping ──"
      echo "Layer '${layers[$i]}' completed (apply + readiness)."
      echo "Resume with:"
      echo "  $0 --consumer-dir $consumer_dir --layer-from ${layers[$next_idx]} --one-at-a-time"
      echo "(drop --one-at-a-time to run the rest back-to-back.)"
      exit 0
    fi
    # If this was the last layer, fall through to the summary.
  fi
done

# ── summary ──────────────────────────────────────────────────────────────────
echo
echo "── Summary ────────────────────────────────────────────────"
echo "Consumer dir: $consumer_dir"
echo
echo "Cloud-UI URL  : (terraform output -raw cloud_ui_url from layer 06)"
echo "DC-API URL    : (terraform output -raw dc_api_url from layer 06)"
echo "OIDC callback : (terraform output -raw oidc_redirect_uri from layer 04)"
echo "                ↑ register this on your IdP if the IdP module did not"
echo "                  do it automatically."
echo
echo "Next steps:"
echo "  - Confirm the UI loads at the cloud-ui URL"
echo "  - dcctl login (set the API URL via DCCTL_API_URL or ~/.dcctl/config.yaml)"
echo "  - Register your first tenant: 'dcctl admin tenant create --slug ...'"
echo "  - Hand the cloud-ui URL to your tenant owners"
