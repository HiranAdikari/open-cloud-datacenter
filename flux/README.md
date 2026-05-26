# Flux GitOps for the Open Cloud Data Center

After Terraform brings up the dcapi-controlplane cluster + installs Flux
(layers 01-06 of `examples/consumer/`), Flux owns every workload inside
that cluster. This directory IS the source of truth for what runs there.

## Layout

```
flux/
├── infrastructure/                shared cluster add-ons (every env gets these)
│   ├── sources/                   HelmRepository / OCIRepository sources
│   ├── sealed-secrets/            controller (decrypts SealedSecret CRs)
│   ├── cert-manager/              cert issuance for ingress
│   └── ingress-nginx/             ingress controller
├── platform/                      dc-api stack (shared across envs)
│   └── dc-api/
│       └── base/                  Deployment, Service, ConfigMap, Ingress, etc.
└── clusters/                      per-environment entrypoints
    ├── _template/                 copy this when bringing up a new env
    │   ├── flux-system/           Flux's own bootstrap manifests (filled by 06)
    │   ├── infrastructure.yaml    Kustomization → ../../infrastructure
    │   ├── platform.yaml          Kustomization → ../../platform
    │   ├── sealed-secrets.yaml    per-env encrypted secrets (Asgardeo, GHCR, etc.)
    │   └── kustomization.yaml     overlays for per-env values (hostnames, replicas)
    └── lk-dev/                    reference env
```

## How a change flows

1. Operator edits a YAML in `flux/platform/dc-api/base/` (or per-env overlay).
2. Commit + push to their fork.
3. Flux Source Controller polls the fork every minute, detects the new commit.
4. Flux Kustomize Controller re-renders the Kustomization, diffs against the
   cluster, applies the delta.
5. ~30s later: the change is live. `flux get all` shows the reconciliation.

## How an image rolls out

1. CI builds + pushes `ghcr.io/<org>/dc-api:main-<sha7>`.
2. Flux Image Reflector Controller polls the registry, sees the new tag.
3. Flux Image Policy resolves the new "best" tag (highest semver / newest commit).
4. Flux Image Automation Controller writes the new tag back to the manifest
   marked with `# {"$imagepolicy": "..."}` and commits to the fork.
5. Source Controller picks up the commit → Kustomize Controller applies it.
6. ~3 min total from `docker push` to running pod.

Dev envs auto-commit (instant rollout); prod envs open a PR for review.

## Secrets

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). The
operator runs `kubeseal` locally; the resulting `SealedSecret` is safe to
commit. Only the in-cluster controller can decrypt.

```bash
kubectl create secret generic asgardeo-m2m \
    --from-literal=client_secret="$VALUE" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > flux/clusters/lk-dev/sealed-asgardeo-m2m.yaml
```

Migration path to External Secrets Operator (pulling from AWS Secrets
Manager / Vault) is a drop-in when multi-cluster + central rotation
become real requirements.

## Bringing up a new environment

```bash
cp -r flux/clusters/_template flux/clusters/<your-env>
# edit hostnames + replica counts in kustomization.yaml
# run examples/consumer/06-flux-bootstrap with --env=<your-env>
# wizard seals secrets + commits
# Flux picks it up from there
```
