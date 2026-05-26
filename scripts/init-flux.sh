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

# ── prereq check ─────────────────────────────────────────────────────────────
# Runs BEFORE any prompt. Catches missing tools / unset kubectl context /
# missing sealed-secrets controller before the operator types a single value.
# Only --seal-secrets mode hits the cluster; without that flag we skip the
# cluster checks (only the local-tool check matters for template-rendering).

prereq_check() {
  local fail=0

  echo "── prereq check ──"

  # Local tools we always need.
  for cmd in sed awk; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  ✓ $cmd"
    else
      echo "  ✗ $cmd not on PATH" >&2
      fail=1
    fi
  done

  if $seal_secrets; then
    # Tools we use to talk to the cluster.
    for cmd in kubectl kubeseal openssl; do
      if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✓ $cmd"
      else
        echo "  ✗ $cmd not on PATH" >&2
        fail=1
      fi
    done

    # Cluster reachability.
    if command -v kubectl >/dev/null 2>&1; then
      local current_ctx
      current_ctx="$(kubectl config current-context 2>/dev/null || true)"
      if [[ -z "$current_ctx" ]]; then
        echo "  ✗ no current kubectl context (run: kubectl config use-context <dcapi-controlplane-context>)" >&2
        fail=1
      else
        echo "  ✓ kubectl context: $current_ctx"
        if ! kubectl get namespace sealed-secrets >/dev/null 2>&1; then
          echo "  ✗ namespace 'sealed-secrets' not found in context '$current_ctx'." >&2
          echo "    Is this the dcapi-controlplane cluster? Has Flux Stage A (infrastructure) finished?" >&2
          echo "    Try: kubectl --context=$current_ctx get kustomization -A" >&2
          fail=1
        elif ! kubectl --namespace=sealed-secrets get deploy sealed-secrets-controller >/dev/null 2>&1; then
          echo "  ✗ sealed-secrets-controller Deployment not found in 'sealed-secrets' ns." >&2
          echo "    Has Flux finished installing the infrastructure HelmReleases?" >&2
          fail=1
        else
          local ready_replicas
          ready_replicas=$(kubectl --namespace=sealed-secrets get deploy sealed-secrets-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
          if [[ "${ready_replicas:-0}" -lt 1 ]]; then
            echo "  ✗ sealed-secrets-controller has $ready_replicas ready replicas — wait for it to come up." >&2
            fail=1
          else
            echo "  ✓ sealed-secrets-controller is Ready ($ready_replicas replica(s))"
          fi
        fi
      fi
    fi
  fi

  if [[ "$fail" -ne 0 ]]; then
    echo
    echo "✗ Prereq check failed — fix the items above and re-run." >&2
    exit 1
  fi
  echo
}

prereq_check

# ── prompt helpers ───────────────────────────────────────────────────────────
# Every prompt loops until the user gives a value. Empty input with no
# default is rejected with a clear message instead of silently accepted.
# Empty input WITH a default is accepted (falls back to the default).

ask() {
  local var="$1" prompt="$2" default="${3:-}" pattern="${4:-}"
  local input=""
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "  $prompt [$default]: " input
      input="${input:-$default}"
    else
      read -r -p "  $prompt: " input
    fi
    if [[ -z "$input" ]]; then
      echo "  ✗ value cannot be empty, try again" >&2
      continue
    fi
    if [[ -n "$pattern" && ! "$input" =~ $pattern ]]; then
      echo "  ✗ value doesn't match expected pattern ($pattern), try again" >&2
      continue
    fi
    break
  done
  printf -v "$var" '%s' "$input"
}

ask_secret() {
  local var="$1" prompt="$2"
  local input=""
  while [[ -z "$input" ]]; do
    read -r -s -p "  $prompt: " input
    echo
    [[ -z "$input" ]] && echo "  ✗ value cannot be empty, try again" >&2
  done
  printf -v "$var" '%s' "$input"
}

# Prompts for a file path, expands `~`, and loops until the file exists.
# Use for paths to existing files we'll read at seal time (kubeconfigs, PEM
# certs). Catches the dead-of-typing case early instead of failing at the
# bottom of the wizard.
ask_file() {
  local var="$1" prompt="$2" default="${3:-}"
  local input=""
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "  $prompt [$default]: " input
      input="${input:-$default}"
    else
      read -r -p "  $prompt: " input
    fi
    if [[ -z "$input" ]]; then
      echo "  ✗ value cannot be empty, try again" >&2
      continue
    fi
    # Expand leading ~ and ~user/. Use eval narrowly on the prefix only,
    # not on the whole string (avoids globbing surprises elsewhere in the path).
    case "$input" in
      "~"|"~/"*) input="${HOME}${input#\~}" ;;
      "~"*)      input="$(eval echo "${input%%/*}")${input#*/}" ;;
    esac
    if [[ -f "$input" ]]; then
      break
    fi
    echo "  ✗ file not found: $input — try again" >&2
  done
  printf -v "$var" '%s' "$input"
}

# ── prompts ──────────────────────────────────────────────────────────────────
# Lightweight regex validators reused below. Wrong by-typo is the common
# failure mode (smushed ports, missing dots) — catching at prompt time is
# infinitely better than catching at terraform-apply time.
HOSTNAME_RE='^[a-zA-Z0-9.-]+$'
IP_RE='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
CIDR_RE='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'
SLUG_RE='^[a-zA-Z0-9_-]+$'

echo "── values for env: $env_name ──"
ask  rancher_hostname  "Rancher hostname"                          ""                  "$HOSTNAME_RE"
ask  dcapi_hostname    "dc-api hostname"                           ""                  "$HOSTNAME_RE"
ask  cloudui_hostname  "cloud-ui hostname"                         ""                  "$HOSTNAME_RE"

# Derive parent domain for BFF cookie sharing.
default_cookie_domain=".$(echo "$cloudui_hostname" | cut -d. -f2-)"
ask  bff_cookie_domain "BFF cookie domain (parent of cloud-ui+dc-api)" "$default_cookie_domain"

ask  asgardeo_org      "Asgardeo org name"                         ""                  "$SLUG_RE"
ask  ghcr_org          "GHCR owner/org (your image stream)"        ""                  "$SLUG_RE"
ask  vpc_external_cidr     "VPC external CIDR (mgmt VLAN)"         "192.168.10.0/24"   "$CIDR_RE"
ask  vpc_external_gateway  "VPC external gateway"                  "192.168.10.254"    "$IP_RE"
ask  ocd_owner         "OCD repo owner (org/user)"                 "wso2"
ask  ocd_repo          "OCD repo name"                             "open-cloud-datacenter"
ask  ocd_ref           "OCD pin (tag like vX.Y.Z, or branch name)" "spike/flux-gitops"

# Heuristic: a value matching ^v[0-9]+\.[0-9]+ is a release tag; anything
# else is treated as a branch. Determines whether sources.yaml's
# GitRepository.spec.ref uses `tag:` or `branch:`.
if [[ "$ocd_ref" =~ ^v[0-9]+\.[0-9]+ ]]; then
  ocd_ref_field="tag"
else
  ocd_ref_field="branch"
fi

if $seal_secrets; then
  echo "── secret values (sealed to cluster, never logged) ──"
  ask_secret rancher_admin_token       "Rancher admin token (from layer 02 output)"
  ask        harvester_cred_id         "Harvester cloud_credential_id (from layer 02-management output, e.g. cattle-global-data:cc-xxxxx)"
  ask_file   harvester_kubeconfig_path "Path to Harvester kubeconfig file"
  ask_secret bff_client_id             "Asgardeo BFF client_id (cloud-ui-bff app, from layer 03 output)"
  ask_secret bff_client_secret         "Asgardeo BFF client_secret"
  ask_secret ghcr_pat                  "GHCR personal-access token (read:packages)"

  echo
  echo "  Ingress TLS cert (covers $dcapi_hostname AND $cloudui_hostname)"
  ask  tls_source "  source: [s]elf-signed (generated now) | [b]yo (path to existing PEM files)" "s"
  if [[ "$tls_source" == "b" ]]; then
    ask_file tls_crt_path "  Path to TLS cert PEM (full chain)"
    ask_file tls_key_path "  Path to TLS key PEM"
  fi
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
    -e "s|github.com/wso2/open-cloud-datacenter|github.com/$ocd_owner/$ocd_repo|g" \
    -e "s|    tag: v0\\.9\\.0|    $ocd_ref_field: $ocd_ref|g" \
    "$src" > "$dst"
  echo "  wrote $dst"
}

ask  git_branch        "Consumer-repo branch Flux watches + commits bumps to"  "spike/flux-gitops"

subst "$template_dir/sources.yaml"          "$target_dir/sources.yaml"
subst "$template_dir/infrastructure.yaml"   "$target_dir/infrastructure.yaml"
subst "$template_dir/platform.yaml"         "$target_dir/platform.yaml"
subst "$template_dir/platform-overlay/kustomization.yaml" "$target_dir/platform-overlay/kustomization.yaml"

# Image Update Automation — bumps Deployment image tags in-place + commits
# back to this repo. Needs the env name + branch substituted into the
# placeholders.
sed \
  -e "s|CHANGE-ME-env|$env_name|g" \
  -e "s|CHANGE-ME-git-branch|$git_branch|g" \
  -e "s|CHANGE-ME-parent-domain|${bff_cookie_domain#.}|g" \
  "$template_dir/image-update-automation.yaml" > "$target_dir/image-update-automation.yaml"
echo "  wrote $target_dir/image-update-automation.yaml"

# Consumer-side README (not a copy of the OCD template's own README —
# that one is meant for someone READING the template upstream; this one
# is for someone looking at the rendered overlay in their consumer repo).
cat > "$target_dir/README.md" <<README
# Flux overlay — $env_name

This directory was generated by \`scripts/init-flux.sh\` from
OCD's \`examples/consumer/flux/\` template. Flux running in the
$env_name cluster reconciles this path from this repo.

## Layout

- \`sources.yaml\` — Flux GitRepository CRs (OCD + this repo).
- \`infrastructure.yaml\` — Flux Kustomization for the shared add-ons
  (sealed-secrets, cert-manager, ingress-nginx) sourced from OCD.
- \`platform.yaml\` — Flux Kustomization for \`./platform-overlay/\`,
  this env's overlay on OCD's shared platform.
- \`platform-overlay/kustomization.yaml\` — Kustomize file that
  remote-bases on OCD's \`flux/platform/\` and patches in $env_name
  hostnames + the consumer's GHCR org for image automation.
- \`sealed-*.yaml\` — sealed secrets generated by the wizard's
  \`--seal-secrets\` mode. Decryptable only by the in-cluster
  sealed-secrets controller; safe to commit.

## Regenerating

Re-run the wizard to refresh placeholders or pick up template
upstream changes:

\`\`\`bash
/path/to/ocd/scripts/init-flux.sh \\
    --consumer-dir <this-repo-root> \\
    --env-name $env_name \\
    --force
\`\`\`

## Upgrading OCD

Bump the \`tag:\` in \`sources.yaml\` and \`?ref=\` in
\`platform-overlay/kustomization.yaml\` to a newer OCD release,
commit, push. Flux applies on the next reconcile.

## Adding env-specific resources

Drop the YAML alongside \`platform-overlay/kustomization.yaml\`
and add it to that file's \`resources:\` list. Patches against
the shared OCD platform also go in that file.
README
echo "  wrote $target_dir/README.md"

# ── seal secrets ─────────────────────────────────────────────────────────────
# (prereqs were checked at the top of the seal-secrets block — kubectl,
# kubeseal, current context, sealed-secrets controller all verified before
# we asked for any secret values).
if $seal_secrets; then
  echo
  echo "── sealing secrets ──"

  cert_pem="$(mktemp)"
  trap 'rm -f "$cert_pem"' EXIT
  kubeseal \
    --controller-namespace=sealed-secrets \
    --controller-name=sealed-secrets-controller \
    --fetch-cert \
    > "$cert_pem"
  echo "  ✓ fetched sealed-secrets controller cert"

  # Generate locally-random values so re-runs don't rotate them.
  # The user can edit + re-seal manually if rotation IS desired.
  postgres_password="$(openssl rand -hex 12)"
  bff_session_secret="$(openssl rand -base64 32)"

  # Compose the DCAPI_OIDC_AUDIENCE list from the three Asgardeo client IDs.
  # Wizard already has bff_client_id; the rancher-sso client_id + cloud-ui SPA
  # client_id come from layer 04 (asgardeo-auth) outputs. Asked here once.
  ask  rancher_oidc_client_id  "Asgardeo rancher-sso client_id (from layer 03 output)"
  ask  cloud_ui_client_id      "Asgardeo cloud-ui SPA client_id (from layer 03 output)"
  oidc_audience="$rancher_oidc_client_id,$bff_client_id,$cloud_ui_client_id"

  seal() {
    local name="$1" namespace="$2"; shift 2
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

  # Filename suffix so the same secret name in two namespaces produces two
  # different files on disk (sealed-secrets-controller distinguishes by
  # namespace, but the filesystem doesn't).
  seal_dockerconfig() {
    local filename="$1" name="$2" namespace="$3" username="$4" pat="$5"
    kubectl create secret docker-registry "$name" \
      --namespace="$namespace" \
      --docker-server=ghcr.io \
      --docker-username="$username" \
      --docker-password="$pat" \
      --dry-run=client -o yaml \
    | kubeseal \
        --cert "$cert_pem" \
        --format yaml \
        --namespace="$namespace" \
        --name="$name" \
    > "$target_dir/$filename"
    echo "  wrote $filename"
  }

  # Postgres password (consumed by the dc-postgres StatefulSet).
  seal dc-postgres-secret dc-system \
       --from-literal=password="$postgres_password"

  # dc-api's main env Secret. Composite — every DCAPI_* env var that's
  # sensitive lives in this single Secret, mounted via envFrom in the
  # Deployment.
  seal dc-api-secrets dc-system \
       --from-literal=DCAPI_DB_URL="postgres://dc_api:${postgres_password}@dc-postgres.dc-system:5432/dc_api?sslmode=disable" \
       --from-literal=DCAPI_OIDC_AUDIENCE="$oidc_audience" \
       --from-literal=DCAPI_RANCHER_TOKEN="$rancher_admin_token" \
       --from-literal=DCAPI_RANCHER_HARVESTER_CREDENTIAL="$harvester_cred_id" \
       --from-literal=DCAPI_OPERATOR_SSH_KEY="" \
       --from-literal=DCAPI_OPERATOR_PASSWORD="" \
       --from-literal=DCAPI_BFF_CLIENT_ID="$bff_client_id" \
       --from-literal=DCAPI_BFF_CLIENT_SECRET="$bff_client_secret" \
       --from-literal=DCAPI_BFF_SESSION_SECRET="$bff_session_secret" \
       --from-file=DCAPI_HARVESTER_KUBECONFIG="$harvester_kubeconfig_path"

  # GHCR image-pull secret. Two namespaces:
  #  - dc-system: used by Deployments' imagePullSecrets to fetch private images
  #  - flux-system: used by ImageRepository CRs to scan private GHCR for new tags
  seal_dockerconfig sealed-ghcr-pull-secret.yaml             ghcr-pull-secret dc-system    "$ghcr_org" "$ghcr_pat"
  seal_dockerconfig sealed-ghcr-pull-secret-flux-system.yaml ghcr-pull-secret flux-system  "$ghcr_org" "$ghcr_pat"

  # dc-api-tls — the Secret both Ingresses (dc-api + cloud-ui) reference.
  # Either generate self-signed with both hostnames in SANs, or seal an
  # operator-supplied PEM pair.
  if [[ "$tls_source" == "b" ]]; then
    tls_crt_pem="$(cat "$tls_crt_path")"
    tls_key_pem="$(cat "$tls_key_path")"
  else
    echo "  generating self-signed cert (1yr) for $dcapi_hostname + $cloudui_hostname"
    tls_workdir="$(mktemp -d)"
    trap 'rm -rf "$tls_workdir"' EXIT
    openssl req -x509 -nodes -newkey rsa:4096 \
      -keyout "$tls_workdir/tls.key" -out "$tls_workdir/tls.crt" \
      -days 365 \
      -subj "/CN=$dcapi_hostname/O=Open Cloud Datacenter" \
      -addext "subjectAltName=DNS:$dcapi_hostname,DNS:$cloudui_hostname" \
      2>/dev/null
    tls_crt_pem="$(cat "$tls_workdir/tls.crt")"
    tls_key_pem="$(cat "$tls_workdir/tls.key")"
  fi

  # kubernetes.io/tls Secret type. Wrap in a temp file so the literal multi-
  # line PEM doesn't get mangled by shell arg passing.
  tls_crt_f="$(mktemp)"; printf '%s' "$tls_crt_pem" > "$tls_crt_f"
  tls_key_f="$(mktemp)"; printf '%s' "$tls_key_pem" > "$tls_key_f"
  kubectl create secret tls dc-api-tls \
    --namespace=dc-system \
    --cert="$tls_crt_f" --key="$tls_key_f" \
    --dry-run=client -o yaml \
  | kubeseal --cert "$cert_pem" --format yaml \
      --namespace=dc-system --name=dc-api-tls \
  > "$target_dir/sealed-dc-api-tls.yaml"
  rm -f "$tls_crt_f" "$tls_key_f"
  echo "  wrote sealed-dc-api-tls.yaml"

  # Rewrite the sealed-secret block in platform-overlay/kustomization.yaml
  # so it references the sealed-*.yaml files we just produced. awk's output
  # goes to a temp file then mv'd into place — never sed -i (banned on macOS
  # because BSD sed silently truncates).
  local_ks="$target_dir/platform-overlay/kustomization.yaml"
  awk '
    /^  # Sealed secrets the wizard drops/ {
      print "  # Sealed secrets generated by scripts/init-flux.sh --seal-secrets."
      print "  - ../sealed-dc-postgres-secret.yaml"
      print "  - ../sealed-dc-api-secrets.yaml"
      print "  - ../sealed-dc-api-tls.yaml"
      print "  - ../sealed-ghcr-pull-secret.yaml"
      print "  - ../sealed-ghcr-pull-secret-flux-system.yaml"
      skip = 1
      next
    }
    /^[^ ]/ { skip = 0 }
    skip && /^  # - / { next }
    skip && /^  - \.\./ { next }
    { print }
  ' "$local_ks" > "$local_ks.new"
  mv "$local_ks.new" "$local_ks"
  echo "  ✓ rewired sealed-secret references in kustomization.yaml"
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
