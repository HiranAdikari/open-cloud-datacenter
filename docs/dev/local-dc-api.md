# Running dc-api locally against the live dev cluster

CI is gated on the in-cluster ARC runner and pushes take ~3 minutes per
iteration. For tight iteration on backend code we run dc-api locally on
the workstation, pointed at the live Harvester + Rancher + Asgardeo, with
the live Postgres reached via `kubectl port-forward`.

This is faster than CI but mixes local writes with prod state. Use it for
iterating on cluster/handler/provider code, NOT for running long-lived
experiments — the prod reconciler in the cluster also writes to the same
DB.

## Prerequisites

- VPN reachable to harvester-dev (KUBECONFIG context: `dcapi-controlplane-rke2`).
- `kubectl`, `jq`, `psql`, and a valid `dcctl` token (`dcctl login`).
- Go toolchain matching `dc-api/go.mod`.

## One-time setup

The bootstrap script lives at `docs/dev/dc-api-local-env.sh` — source it
to populate `DCAPI_*` env from the prod Secret + ConfigMap, with three
overrides:

- `DCAPI_DB_URL` → `postgres://...@localhost:15432/dc_api?sslmode=disable`
  (port-forwarded)
- `DCAPI_LISTEN_ADDR` → `:18080` (avoid colliding with anything on `:8080`)
- `DCAPI_LOG_LEVEL` → `debug`

## Iteration loop

```bash
# 1. Port-forward postgres (background; leave running).
kubectl --context dcapi-controlplane-rke2 -n dc-system \
  port-forward svc/dc-postgres 15432:5432 > /tmp/pgpf.log 2>&1 &
echo $! > /tmp/pgpf.pid

# 2. Build + run dc-api locally.
cd dc-api
go build -o /tmp/dc-api-local ./cmd/dc-api/
source ../docs/dev/dc-api-local-env.sh
nohup /tmp/dc-api-local > /tmp/dc-api-local.log 2>&1 &
echo $! > /tmp/dc-api-local.pid

# 3. Drive it.
TOKEN=$(jq -r '.access_token' ~/.dcctl/credentials.json)
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:18080/healthz
curl -s -X POST http://localhost:18080/v1/clusters \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"test","k8s_version":"v1.33.10+rke2r3", ...}'

# 4. After code edits, restart:
kill $(cat /tmp/dc-api-local.pid)
go build -o /tmp/dc-api-local ./cmd/dc-api/
nohup /tmp/dc-api-local > /tmp/dc-api-local.log 2>&1 &
echo $! > /tmp/dc-api-local.pid
```

`source dc-api-local-env.sh` re-runs `kubectl get secret/cm` each time
— if a config value changed in the cluster, you pick it up on the next
source.

## What to watch out for

### Reconciler race

The prod dc-api pod in the cluster runs its own 60-second reconciler
against the same Postgres. If your local dc-api creates a Resource row
in PENDING state, both reconcilers will poll Steve to update its status.
This is mostly harmless (reads are idempotent), but if you're testing
reconciler logic specifically, you want **exclusive** access:

```bash
# Scale prod dc-api to 0 for the duration of the test.
kubectl --context dcapi-controlplane-rke2 -n dc-system scale deploy/dc-api --replicas=0

# ... iterate ...

# Restore when done.
kubectl --context dcapi-controlplane-rke2 -n dc-system scale deploy/dc-api --replicas=1
```

### Postgres port-forward drops

`kubectl port-forward` can die silently on network blips (Cloudflare
HTTP/2 stream timeout ~60s). The Go pgx pool will reconnect on the next
query, but it'll get connection-refused until you restart the
port-forward. Check `/tmp/pgpf.log` if dc-api starts erroring on DB
queries:

```bash
kubectl --context dcapi-controlplane-rke2 -n dc-system \
  port-forward svc/dc-postgres 15432:5432 > /tmp/pgpf.log 2>&1 &
echo $! > /tmp/pgpf.pid
```

### Token expiry

dcctl tokens expire in 1 hour. If `curl` starts returning
`Unauthorized: invalid token`, run `dcctl login` and re-export. Same
token works against local + prod dc-api because both trust the same
Asgardeo issuer/audience.

### Multi-line env values

`DCAPI_HARVESTER_KUBECONFIG` is a multi-line base64-encoded kubeconfig
embedded in the Secret. The bootstrap script handles quoting correctly
— don't try to `export $(cat ...)` directly, it'll break on the
newlines.

## Cleanup

```bash
kill $(cat /tmp/dc-api-local.pid) 2>/dev/null
kill $(cat /tmp/pgpf.pid) 2>/dev/null
rm -f /tmp/dc-api-local.pid /tmp/pgpf.pid /tmp/dc-api-local.log /tmp/pgpf.log
```

## When to use this vs CI

- **Local**: code iteration on dc-api handlers, providers, reconciler,
  any change <50 LOC; debugging a specific failure case live.
- **CI**: anything that touches schema migrations (test against a fresh
  testcontainers DB first), anything you'd ship to prod, anything that
  needs the validation gate of integration tests in CI.
