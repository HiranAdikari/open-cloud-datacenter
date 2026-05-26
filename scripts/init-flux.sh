#!/usr/bin/env bash
#
# init-flux.sh — interactive wizard for first-time Flux GitOps setup.
#
# What it does:
#   1. Asks for env name, hostnames, Asgardeo + GHCR creds, etc.
#   2. Renders the examples/consumer/flux/ template into
#      <consumer-repo>/environments/<env>/flux/ with placeholders filled.
#   3. (Optional, if --seal-secrets is passed) Connects to the cluster
#      via the layer-05 kubeconfig, fetches the sealed-secrets
#      controller cert, runs `kubeseal` on each secret value, and writes
#      sealed-*.yaml alongside the overlay.
#   4. Commits + pushes to the consumer repo on a feature branch.
#
# Prerequisites the wizard expects but doesn't install:
#   - bash, git, jq, yq
#   - kubeseal (only if --seal-secrets)
#   - kubectl with a context pointing at the dcapi-controlplane cluster
#     (only if --seal-secrets)
#
# Usage:
#   ./scripts/init-flux.sh \
#       --consumer-dir ../wso2-datacenter-project \
#       --env-name lk-dev \
#       [--seal-secrets]
#
# This is a SKELETON. The interactive flow + secret sealing are TODOs;
# the immediate purpose is to capture the wizard's surface so the
# consumer-template + OCD library can be exercised manually first.

set -euo pipefail

consumer_dir=""
env_name=""
seal_secrets=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer-dir)  consumer_dir="$2"; shift 2 ;;
    --env-name)      env_name="$2"; shift 2 ;;
    --seal-secrets)  seal_secrets=true; shift ;;
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

if [[ -z "$consumer_dir" || -z "$env_name" ]]; then
  echo "missing required: --consumer-dir + --env-name" >&2
  exit 4
fi

ocd_root="$(cd "$(dirname "$0")/.." && pwd)"
target_dir="$consumer_dir/environments/$env_name/flux"
template_dir="$ocd_root/examples/consumer/flux"

echo "── init-flux ────────────────────────────────────────────────"
echo "  OCD root:      $ocd_root"
echo "  Consumer:      $consumer_dir"
echo "  Env:           $env_name"
echo "  Target:        $target_dir"
echo

if [[ -e "$target_dir" ]]; then
  echo "  ✗ $target_dir already exists. Rename or delete it first." >&2
  exit 1
fi

# ── TODO 1: prompt for values ─────────────────────────────────────────────
# read -p "Rancher hostname: " rancher_hostname
# read -p "DC-API hostname: "  dcapi_hostname
# read -p "Cloud-UI hostname: " cloud_ui_hostname
# read -p "Asgardeo org name: " asgardeo_org
# read -p "GHCR owner/org: " ghcr_owner
# … etc.

# ── TODO 2: copy template and replace placeholders ─────────────────────────
# cp -r "$template_dir" "$target_dir"
# sed -i '' "s/CHANGE-ME-env/$env_name/g" "$target_dir/platform.yaml"
# sed -i '' "s/CHANGE-ME-asgardeo-org/$asgardeo_org/g" \
#   "$target_dir/platform-overlay/kustomization.yaml"
# … etc.

# ── TODO 3: seal secrets (if --seal-secrets) ───────────────────────────────
# if $seal_secrets; then
#   kubeseal --fetch-cert > /tmp/sealed-secrets-cert.pem
#   for s in asgardeo-m2m rancher-token harvester-kubeconfig ghcr-pull dc-api-bff; do
#     kubectl create secret generic "$s" --dry-run=client -o yaml \
#       --from-literal=... \
#       | kubeseal --cert /tmp/sealed-secrets-cert.pem --format yaml \
#       > "$target_dir/sealed-$s.yaml"
#   done
# fi

# ── TODO 4: commit + push ─────────────────────────────────────────────────
# (cd "$consumer_dir" && \
#    git checkout -B "flux/init-$env_name" && \
#    git add "environments/$env_name/flux" && \
#    git commit -m "Add Flux overlay for $env_name env" && \
#    git push -u origin "flux/init-$env_name")

cat <<EOF
This script is a skeleton. To exercise the model manually for now:

  1. cp -r $template_dir $target_dir
  2. \$EDITOR $target_dir/**/*.yaml    # replace CHANGE-ME placeholders
  3. cd $consumer_dir && git add environments/$env_name/flux && git commit -m "…"
  4. Apply the 06-flux-bootstrap TF layer with env_name=$env_name
  5. After Flux + sealed-secrets controller are up:
       kubeseal --fetch-cert > /tmp/cert.pem
       # generate each sealed secret with kubeseal and commit them

The wizard implementation will fold these steps into a single
interactive run. See the TODOs in this file.
EOF
