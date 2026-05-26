#!/usr/bin/env bash
#
# init-flux.sh — render the consumer Flux overlay for a new env.
#
# Reads the template at <ocd-repo>/examples/consumer/flux/ and writes a
# filled-in copy at <consumer-dir>/environments/<env>/flux/ with every
# CHANGE-ME placeholder substituted with operator-supplied values.
#
# If --seal-secrets is passed, also fetches the sealed-secrets controller
# certificate from the live cluster, prompts for secret values, runs
# kubeseal on each one, drops the resulting sealed-*.yaml alongside the
# overlay, and uncomments the references in platform-overlay/kustomization.yaml.
#
# Usage:
#   ./scripts/init-flux.sh \
#       --consumer-dir /path/to/wso2-datacenter-project \
#       --env-name lk-dev \
#       [--seal-secrets]                # requires KUBECONFIG pointed at dcapi-controlplane
#       [--force]                       # overwrite existing target dir
#
# Prereqs:
#   bash, sed (read-only mode only), git
#   For --seal-secrets: kubectl, kubeseal, $KUBECONFIG set
#
# Exits non-zero on validation failure or any prompt cancellation.

set -euo pipefail

# ── arg parse ────────────────────────────────────────────────────────────────
consumer_dir=""
env_name=""
seal_secrets=false
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer-dir) consumer_dir="$2"; shift 2 ;;
    --env-name)     env_name="$2"; shift 2 ;;
    --seal-secrets) seal_secrets=true; shift ;;
    --force)        force=true; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//;$d'
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 4
      ;;
  esac
done

[[ -z "$consumer_dir" || -z "$env_name" ]] && {
  echo "missing required: --consumer-dir + --env-name (use --help)" >&2
  exit 4
}

# Resolve paths
ocd_root="$(cd "$(dirname "$0")/.." && pwd)"
template_dir="$ocd_root/examples/consumer/flux"
target_dir="$consumer_dir/environments/$env_name/flux"

[[ ! -d "$template_dir" ]] && {
  echo "✗ template not found: $template_dir" >&2
  exit 1
}
[[ ! -d "$consumer_dir" ]] && {
  echo "✗ consumer dir not found: $consumer_dir" >&2
  exit 1
}

if [[ -e "$target_dir" ]]; then
  if $force; then
    echo "  ! --force given; overwriting $target_dir"
    rm -rf "$target_dir"
  else
    echo "✗ $target_dir already exists. Pass --force to overwrite." >&2
    exit 1
  fi
fi

echo "── init-flux ────────────────────────────────────────────────"
echo "  OCD template:  $template_dir"
echo "  Consumer:      $consumer_dir"
echo "  Target:        $target_dir"
echo "  Seal secrets:  $seal_secrets"
echo

# ── prompt helpers ───────────────────────────────────────────────────────────
ask() {
  local var="$1" prompt="$2" default="${3:-}"
  local input
  if [[ -n "$default" ]]; then
    read -r -p "  $prompt [$default]: " input
    input="${input:-$default}"
  else
    read -r -p "  $prompt: " input
  fi
  printf -v "$var" '%s' "$input"
}

ask_secret() {
  local var="$1" prompt="$2"
  local input
  read -r -s -p "  $prompt: " input
  echo
  printf -v "$var" '%s' "$input"
}

# ── prompts ──────────────────────────────────────────────────────────────────
echo "── values for env: $env_name ──"
ask  rancher_hostname  "Rancher hostname"
ask  dcapi_hostname    "dc-api hostname"
ask  cloudui_hostname  "cloud-ui hostname"

# Derive parent domain for BFF cookie sharing.
default_cookie_domain=".$(echo "$cloudui_hostname" | cut -d. -f2-)"
ask  bff_cookie_domain "BFF cookie domain (parent of cloud-ui+dc-api)" "$default_cookie_domain"

ask  asgardeo_org      "Asgardeo org name"
ask  ghcr_org          "GHCR owner/org (your image stream)"
ask  vpc_external_cidr     "VPC external CIDR (mgmt VLAN)"        "192.168.10.0/24"
ask  vpc_external_gateway  "VPC external gateway"                  "192.168.10.254"
ask  ocd_ref           "OCD pin (tag or branch)"                   "spike/flux-gitops"

if $seal_secrets; then
  echo
  echo "── secret values (sealed to cluster, never logged) ──"
  ask_secret asgardeo_m2m_secret    "Asgardeo M2M client secret"
  ask_secret rancher_admin_token    "Rancher admin token"
  ask_secret ghcr_pat               "GHCR personal-access token"
  ask        harvester_kubeconfig_path "Path to Harvester kubeconfig (will be base64'd)"
fi

# ── render template ──────────────────────────────────────────────────────────
echo
echo "── rendering template ──"
mkdir -p "$target_dir/platform-overlay"

# subst() reads a template file and writes the placeholder-replaced output.
# All sed usage is READ-ONLY (input -> stdout -> redirected to target),
# never -i in-place — BSD sed on macOS silently truncates with -i.
subst() {
  local src="$1" dst="$2"
  sed \
    -e "s|CHANGE-ME-rancher-hostname|$rancher_hostname|g" \
    -e "s|CHANGE-ME-dcapi-hostname|$dcapi_hostname|g" \
    -e "s|CHANGE-ME-cloud-ui-hostname|$cloudui_hostname|g" \
    -e "s|CHANGE-ME-asgardeo-org|$asgardeo_org|g" \
    -e "s|CHANGE-ME-org|$ghcr_org|g" \
    -e "s|\\.CHANGE-ME-parent-domain|$bff_cookie_domain|g" \
    -e "s|CHANGE-ME-cidr|$vpc_external_cidr|g" \
    -e "s|CHANGE-ME-gateway|$vpc_external_gateway|g" \
    -e "s|CHANGE-ME-env|$env_name|g" \
    -e "s|ref=v0\\.9\\.0|ref=$ocd_ref|g" \
    "$src" > "$dst"
  echo "  wrote $dst"
}

subst "$template_dir/sources.yaml"          "$target_dir/sources.yaml"
subst "$template_dir/infrastructure.yaml"   "$target_dir/infrastructure.yaml"
subst "$template_dir/platform.yaml"         "$target_dir/platform.yaml"
subst "$template_dir/platform-overlay/kustomization.yaml" "$target_dir/platform-overlay/kustomization.yaml"
[[ -f "$template_dir/README.md" ]] && subst "$template_dir/README.md" "$target_dir/README.md"

# ── seal secrets ─────────────────────────────────────────────────────────────
if $seal_secrets; then
  echo
  echo "── sealing secrets ──"
  : "${KUBECONFIG:?KUBECONFIG must be set and pointed at dcapi-controlplane}"
  command -v kubeseal >/dev/null || { echo "✗ kubeseal not on PATH" >&2; exit 1; }
  command -v kubectl  >/dev/null || { echo "✗ kubectl not on PATH"  >&2; exit 1; }

  cert_pem="$(mktemp)"
  trap 'rm -f "$cert_pem"' EXIT
  kubeseal \
    --controller-namespace=sealed-secrets \
    --controller-name=sealed-secrets-controller \
    --fetch-cert \
    > "$cert_pem"
  echo "  ✓ fetched sealed-secrets controller cert"

  seal() {
    local name="$1" namespace="$2"; shift 2
    # remaining args = --from-literal=k=v pairs
    kubectl create secret generic "$name" \
      --namespace="$namespace" \
      --dry-run=client -o yaml \
      "$@" \
    | kubeseal \
        --cert "$cert_pem" \
        --format yaml \
        --namespace="$namespace" \
        --name="$name" \
    > "$target_dir/sealed-$name.yaml"
    echo "  wrote sealed-$name.yaml"
  }

  seal asgardeo-m2m   dc-system \
       --from-literal=client_secret="$asgardeo_m2m_secret"
  seal rancher-token  dc-system \
       --from-literal=token="$rancher_admin_token"
  seal ghcr-pull      dc-system \
       --from-literal=.dockerconfigjson="$(printf '{"auths":{"ghcr.io":{"username":"%s","password":"%s","auth":"%s"}}}' \
            "$ghcr_org" "$ghcr_pat" "$(printf '%s:%s' "$ghcr_org" "$ghcr_pat" | base64)")"
  seal harvester-kubeconfig dc-webhook \
       --from-file=DCWEBHOOK_KUBECONFIG="$harvester_kubeconfig_path"

  # Uncomment the sealed-secret references in kustomization.yaml.
  # Read-only sed -> redirect to a temp -> mv. No -i on macOS.
  local_ks="$target_dir/platform-overlay/kustomization.yaml"
  sed \
    -e 's|^  # - ../sealed-asgardeo-m2m.yaml|  - ../sealed-asgardeo-m2m.yaml|' \
    -e 's|^  # - ../sealed-rancher-token.yaml|  - ../sealed-rancher-token.yaml|' \
    -e 's|^  # - ../sealed-ghcr-pull.yaml|  - ../sealed-ghcr-pull.yaml|' \
    -e 's|^  # - ../sealed-harvester-kubeconfig.yaml|  - ../sealed-harvester-kubeconfig.yaml|' \
    "$local_ks" > "$local_ks.new"
  mv "$local_ks.new" "$local_ks"
  echo "  ✓ uncommented sealed-secret resources in kustomization.yaml"
fi

# ── done ─────────────────────────────────────────────────────────────────────
echo
echo "── done ────────────────────────────────────────────────────"
echo "  Wrote: $target_dir/"
echo
echo "  Next steps:"
echo "    cd $consumer_dir"
echo "    git add environments/$env_name/flux"
echo "    git commit -m 'Add Flux overlay for $env_name'"
echo "    git push"
if ! $seal_secrets; then
  echo
  echo "  Then re-run with --seal-secrets (after cluster + sealed-secrets controller are up):"
  echo "    KUBECONFIG=... $0 --consumer-dir $consumer_dir --env-name $env_name --seal-secrets --force"
fi
echo
echo "  After commit + push: apply the 06-flux-bootstrap TF layer to install"
echo "  Flux and point it at $target_dir."
