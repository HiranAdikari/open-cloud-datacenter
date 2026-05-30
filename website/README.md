# Product site

Public marketing + documentation site, served as a static site via GitHub
Pages (`.github/workflows/site.yml`). Plain static HTML/CSS/JS — no framework.

## Wired to real OCD sources

- **API** — `api/index.html` renders the **real** `dc-api/openapi.yaml`
  (copied to `api/openapi.yaml`) with Redoc: 54 paths / 92 operations.
- **CLI** — `docs/cli/index.html` is the **real** `dcctl` command tree
  (login/logout, vm, cluster, vnet, subnet, peering, network, image,
  bastion, keyvault, tenant, project, admin).
- **Docs** — `docs/*.html` are generated from the repo's real `docs/*.md`
  (local-dev, architecture, rbac, ops-bootstrap) by `tools/build-docs.mjs`.

## Regenerate

```bash
# API: refresh the spec copy from the controlplane tree
cp <controlplane>/dc-api/openapi.yaml website/api/openapi.yaml

# Docs: re-render from the real markdown (uses npx marked)
node website/tools/build-docs.mjs
```

The CLI page is authored from the `dcctl` cobra command tree; refresh it by
re-deriving the command list from `dcctl/cmd/`.

## Preview locally

```bash
python3 -m http.server -d website 8088
# open http://localhost:8088
```

## Deploy

Pushing `website/**` to `main` runs the Pages workflow. Requires a maintainer
to enable **Settings → Pages → Source: GitHub Actions** (repository admin).

## Product name

Working name **OpenStrato** (pending an availability check). It appears as the
two-tone wordmark `<b>Open</b><span>Strato</span>`, the string `OpenStrato`,
and `openstrato` in example domains. Rename by replacing those tokens.

## Still to do

- **Landing copy is still the designer's placeholder** — the "2.4k" stars, the
  "v0.5" banner, and feature claims are dummy; GitHub links point to `#`; the
  `openstrato.dev` domains aren't real.
- **Genericize internal wording** — the real spec/CLI/docs carry upstream
  "DC-API / Sovereign Cloud / Asgardeo / Rancher / Harvester" terms that clash
  with the generic OpenStrato framing.
- **Cross-branch sourcing** — the spec and docs live on the controlplane
  branch; the build currently reads them from a local checkout. CI wiring that
  pulls them at build time is follow-up.
