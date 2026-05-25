#!/bin/bash
# Source to populate DCAPI_* env from the live cluster, with local overrides.
# Pulls live values from the prod dc-api Secret + ConfigMap (so you don't
# drift from prod config), then overrides DB URL (port-forwarded) + listen
# port (:18080) + log level (debug).
#
# Companion: docs/dev/local-dc-api.md

set -euo pipefail
CTX=dcapi-controlplane-rke2
NS=dc-system

ENVFILE=$(mktemp)
trap "rm -f $ENVFILE" EXIT

# Secrets — base64-decode each value and emit `export KEY=<single-quoted>`.
# Single quotes preserve newlines + special chars inside multi-line YAML
# values like the embedded kubeconfig. `'\''` escapes any literal single
# quotes that may appear in passwords.
kubectl --context "$CTX" -n "$NS" get secret dc-api-secrets -o json \
  | jq -r '.data | to_entries[] | "\(.key)\t\(.value)"' \
  | while IFS=$'\t' read -r k v; do
      decoded=$(printf '%s' "$v" | base64 -d)
      escaped=$(printf '%s' "$decoded" | sed "s/'/'\\\\''/g")
      printf "export %s='%s'\n" "$k" "$escaped" >> "$ENVFILE"
    done

# ConfigMap — same pattern, plain values.
kubectl --context "$CTX" -n "$NS" get configmap dc-api-config -o json \
  | jq -r '.data | to_entries[] | "\(.key)\t\(.value)"' \
  | while IFS=$'\t' read -r k v; do
      escaped=$(printf '%s' "$v" | sed "s/'/'\\\\''/g")
      printf "export %s='%s'\n" "$k" "$escaped" >> "$ENVFILE"
    done

source "$ENVFILE"

# Local overrides — point at port-forwarded postgres, different listen
# addr (don't collide with anything on :8080), debug logs.
PG_PW=$(printf '%s' "$DCAPI_DB_URL" | sed -E 's|.*dc_api:([^@]+)@.*|\1|')
export DCAPI_DB_URL="postgres://dc_api:$PG_PW@localhost:15432/dc_api?sslmode=disable"
export DCAPI_LISTEN_ADDR=":18080"
export DCAPI_LOG_LEVEL=debug

echo "env loaded — $(env | grep -c '^DCAPI_') DCAPI_* vars"
echo "  DB → localhost:15432 (port-forward), listen → :18080, log → debug"
