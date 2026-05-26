# 06-flux-bootstrap

Final Terraform layer. Installs Flux into the dcapi-controlplane cluster
and points it at the operator's fork of this repo. After this layer
applies, **Terraform stops managing in-cluster workloads** — everything
under `flux/` in the fork is the new source of truth.

## What it does

1. Generates an ECDSA deploy key (kept in this layer's state).
2. Registers the deploy key on the operator's fork via the GitHub API
   (one-time use of `github_token`; the token isn't persisted on the
   cluster).
3. Calls `flux_bootstrap_git`, which:
   - Applies Flux's controller manifests to `flux-system` namespace.
   - Commits `flux/clusters/<env_name>/flux-system/{gotk-components,gotk-sync,kustomization}.yaml`
     to the fork.
   - The committed `GitRepository` + root `Kustomization` cause Flux to
     start reconciling `flux/clusters/<env_name>/` immediately.
4. From this point on: operator commits to fork → Flux reconciles.

## Prerequisites

- Layers 01-05 applied; dcapi-controlplane cluster Ready.
- `flux/clusters/<env_name>/` directory exists in the fork (copied from
  `flux/clusters/_template/`, placeholders replaced).
- `github_token` with `repo` scope (used once; rotate after bootstrap if
  desired).

## After this layer applies

```bash
# Watch Flux's first reconciliation
KUBECONFIG=... kubectl --namespace=flux-system get kustomizations -w

# Expect to see, in order:
#   flux-system    (root)         Ready
#   infrastructure                Ready    (cert-manager, sealed-secrets, ingress-nginx)
#   platform                      Ready    (dc-api Deployment + Service + Ingress)
```

Then the wizard (`scripts/init.sh`) prompts for secrets, seals them
against the now-running Sealed Secrets controller, commits them to the
fork; Flux applies them; dc-api comes fully up.
