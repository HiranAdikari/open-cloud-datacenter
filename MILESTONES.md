# Sovereign Cloud — Milestone Plan

> **Read before starting any task**: If the current task is a bug fix, debugging session,
> or general question, check which milestone it belongs to and whether it unblocks something
> on the M1 checklist before diving deep. Don't let rabbit holes push M1 tasks off the board.

---

## Current Focus: M1 — Foundation (Compute & Clusters)

**Target**: Q2 2026 | **Status**: 🟢 E2E Complete — VM + Cluster proven end-to-end; unit tests pending

### M1 Task Board

#### Phase A: Make it build ✅ DONE (2026-04-24)
- [x] `cd dc-api && go mod tidy && go build ./...` — passes clean
- [x] `cd dcctl && go mod tidy && go build ./...` — passes clean

#### Phase B: Complete stubs ✅ DONE (2026-04-24)
- [x] `harvester/client.go` — `GetVM`: direct Get by `namespace:name`, maps `printableStatus`
- [x] `harvester/client.go` — `DeleteVM`: direct Delete with `PropagationPolicy=Background`
- [x] `harvester/client.go` — `ensureNamespace`: core/v1 namespace create, IsAlreadyExists = OK
- [x] BackendUID format changed to `"namespace:name"` (O(1) lookup, not UID scan)
- [x] cloud-init injected into VM manifest (SSH public key → authorized_keys)
- [x] Auth middleware made pluggable: `AuthConfig{TenantGroupPrefix, AdminGroup}` via env vars
- [x] `config.go` — added `DCAPI_TENANT_GROUP_PREFIX` and `DCAPI_ADMIN_GROUP`
- [x] `README.md` — full project documentation
- [x] `docs/asgardeo-setup.md` — personal Asgardeo account setup guide (9 steps)

#### Phase C: Reconciler ✅ DONE (2026-04-24)
- [x] `internal/reconciler/reconciler.go` — goroutine, ticks every 60s
- [x] `db.ListPending()` — queries PENDING/DELETING resources with a backend_uid
- [x] `db.Delete()` — removes confirmed-deleted resources from PostgreSQL
- [x] Status change detection, audit event on transition, not-found → FAILED / row delete

#### Phase D: dcctl sub-commands ✅ DONE (2026-04-24)
- [x] `dcctl/cmd/get/vm.go` — `dcctl get vm <id>`
- [x] `dcctl/cmd/get/cluster.go` — `dcctl get cluster <id>`
- [x] `dcctl/cmd/delete/vm.go` — `dcctl delete vm <id>` (confirmation prompt, -y flag)
- [x] `dcctl/cmd/delete/cluster.go`
- [x] `dcctl/cmd/create/cluster.go` — `dcctl create cluster --name --version --nodes --cpu --memory`
- [x] `dcctl/cmd/kubeconfig.go` — `dcctl kubeconfig <cluster-id>` (stdout or --file)
- [x] All commands registered in `root.go`; `client.GetRaw()` added for YAML responses

#### Phase E: Infrastructure ✅ DONE (2026-04-24)
- [x] `db/migrate.go` — embedded schema.sql, idempotent check on `pg_tables`, runs at startup
- [x] `dc-api/Dockerfile` — multi-stage (golang:1.22-alpine → distroless/static:nonroot)
- [x] `dc-api/deploy/namespace.yaml` — `dc-system` namespace
- [x] `dc-api/deploy/configmap.yaml` — all non-secret DCAPI_* vars
- [x] `dc-api/deploy/secret.yaml.template` — template for secrets (not committed)
- [x] `dc-api/deploy/postgres.yaml` — StatefulSet + headless Service for lk-dev PostgreSQL
- [x] `dc-api/deploy/deployment.yaml` — Deployment + ClusterIP Service; health probes; nonroot

#### Phase F-bug-fixes: VM bugs fixed during live testing ✅ DONE (2026-04-27)
- [x] cloud-init rewrite: removed `users:` block that broke password/SSH key injection;
      fixed YAML booleans (`False`→`false`, `True`→`true`)
- [x] Reconciler IP ordering: `UpdateIPAddress` moved before status-change short-circuit
      so IPs reported by qemu-guest-agent after ACTIVE transition are now persisted
- [x] `dcctl create vm` polls by default (az-style); `--no-wait` flag for immediate return
- [x] Expired token gives clear "invalid token" error — user runs `dcctl login` to refresh

#### Phase F-sizes: Named VM sizes (Azure-style) ✅ DONE (2026-04-27)
- [x] `models/resource.go` — `VMSize` struct, `Sizes` catalog (small/medium/large/xlarge)
- [x] `db/schema.sql` + `db/migrate.go` — `size TEXT` column (idempotent ALTER on startup)
- [x] `db/db.go` — `size` included in INSERT, Get, ListByTenant, ListPending
- [x] `handlers/vm.go` — `CreateVMRequest` uses `size` string; resolved to CPU/memory/disk
- [x] `handlers/cluster.go` — `CreateClusterRequest` uses `node_size`; `image_name`/`network_name` required
- [x] `rancher/client.go` — removed `vmImage`/`vmNetwork` from Client; reads from `ClusterSpec`
- [x] `config.go` — removed `ClusterVMImage`/`ClusterVMNetwork` env vars
- [x] `dcctl create vm` — `--cpu`/`--memory` replaced by `--size`; `--disk` optional override
- [x] `dcctl create cluster` — `--size`, `--image`, `--network` added; `--cpu`/`--memory` removed
- [x] `dcctl list vms` / `dcctl list clusters` / `dcctl list images` — new `list` command group
- [x] `dcctl get vms` / `dcctl get images` moved to `dcctl list` (get now only for `get <id>`)

#### Phase F-cluster: Cluster E2E fixes ✅ DONE (2026-04-28)
- [x] `rancher/client.go` — `buildNodeUserData()` always installs `qemu-guest-agent` + IPVS
      modules; without it Rancher's provisioner hangs at "Waiting for Node Ref" forever
- [x] `rancher/client.go` — `GetCluster()` rewritten: reads `status.ready` + `Stalled` condition
      instead of non-existent `phase` field (provisioning v2 API); clusters no longer stuck PENDING
- [x] `rancher/client.go` — `GetKubeconfig()` two-step: resolve `status.clusterName` from
      provisioning cluster, then POST `/v3/clusters/<id>?action=generateKubeconfig` (v2 endpoint
      does not expose this action)
- [x] `rancher/client.go` — fixed `memorySize`: was incorrectly multiplied by 1024; Rancher
      treats the value as GiB directly
- [x] `rancher/client.go` — operator SSH key + password injected into all cluster nodes via
      cloud-init for IaaS team break-glass access
- [x] `reconciler.go` — DELETING resources never transition backward to ACTIVE/PENDING;
      Rancher keeps cluster object with `ready=true` during deletion which was re-activating rows
- [x] `handlers/vm.go` — VM delete no longer removes DB row immediately; stays DELETING until
      reconciler confirms via 404 (consistent with cluster behavior)

#### Phase F: Testing & Validation ✅ DONE (2026-04-28)
- [x] `dcctl login` → `dcctl create vm --size medium` → VM reaches ACTIVE → SSH + password work
- [x] IP address appears in `dcctl get vm` after ~60s (qemu-guest-agent pipeline)
- [x] `dcctl delete vm` — stays DELETING; reconciler confirms and removes DB row on 404
- [x] `dcctl create cluster --size medium --image ... --network ...` → ACTIVE → `dcctl kubeconfig`
      → `kubectl get nodes` — full path proven end-to-end
- [ ] `dc-api/internal/api/handlers/vm_test.go` — unit tests (post-E2E, not yet written)

---

## M1.5 — Full RBAC (before M2, after M1 E2E test passes)

**Target**: Q2 2026 | **Status**: 🔵 Designed, not yet implemented

### Why M1 RBAC is not enough
Current: group → tenantID → can only see own resources (tenant isolation).
Missing: roles within a tenant (owner vs member vs viewer), service accounts for CI/CD,
permission checks per operation, and a model that **extends cleanly to the M5 hierarchy
(Organisation → Subscription → Resource Group → Resource)** without a schema rewrite.

### Design principle: scope-polymorphic role assignments (Azure-shaped)

Roles are NOT bound directly to tenants. They're bound to a **scope** — and the scope
type is a string that today only takes the value `tenant`, but tomorrow can also be
`subscription`, `resource_group`, or `resource` without touching existing rows.

This means M1.5's schema is **forward-compatible with M5**. When the hierarchy lands,
no migration of existing role assignments — just new rows with new scope types.

### Role Model
| Role             | Default permissions                                  | Notes |
|------------------|------------------------------------------------------|-------|
| `owner`          | Full CRUD within scope; manage members within scope  | Most permissive |
| `member`         | Create / read / update; cannot delete or manage members | Day-to-day developer role |
| `viewer`         | Read-only within scope                               | Auditors, CI dashboards |
| `platform-admin` | All scopes, all operations (break-glass + automation) | Asgardeo group `dc-admin` short-circuits the membership lookup |

Service accounts get the same role values as humans, but authenticate via a long-lived
DC-API-issued token instead of an OIDC JWT. They're stored as separate principal type
in `role_assignments` so they show up in audit and can be revoked independently.

### Database shape

```sql
-- One table replaces tenant_roles. Polymorphic scope, ready for M5 extension.
CREATE TABLE role_assignments (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    principal_type TEXT NOT NULL,        -- 'user' | 'service_account'
    principal_id   TEXT NOT NULL,        -- JWT 'sub' for users; service_account.id for SAs
    scope_type     TEXT NOT NULL,        -- 'tenant' for M1.5; 'subscription' / 'resource_group' / 'resource' for M5+
    scope_id       TEXT NOT NULL,        -- the slug/UUID of the scoped object
    role           TEXT NOT NULL,        -- 'owner' | 'member' | 'viewer'
    granted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    granted_by     TEXT NOT NULL,        -- principal_id of whoever granted this
    UNIQUE (principal_type, principal_id, scope_type, scope_id, role)
);

CREATE INDEX idx_role_assignments_principal ON role_assignments (principal_type, principal_id);
CREATE INDEX idx_role_assignments_scope     ON role_assignments (scope_type, scope_id);

CREATE TABLE service_accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   TEXT NOT NULL,
    name        TEXT NOT NULL,
    token_hash  TEXT NOT NULL,           -- bcrypt of the issued token; raw token shown to caller exactly once
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used   TIMESTAMPTZ,
    UNIQUE (tenant_id, name)
);
```

### Authorisation check at request time

Every mutating handler calls `requireRole(ctx, minimum)`. The check walks the scope
chain of the request from narrowest → broadest, collecting any role assignments. The
**most permissive** role across the chain is the effective role. In M1.5 the chain has
length 1 (just `tenant`); in M5 it grows to 3 or 4.

```
Action: alice tries DELETE /v1/virtual-machines/<id>

Walk for resource owned by tenant=acme:
  scope_type=tenant, scope_id=acme   → alice has 'member'
  → effective role = member
  → DELETE requires 'owner' → 403
```

### Edge cases (locked)
- **First login with no membership row.** Two policies, configurable via env var:
  - `DCAPI_RBAC_AUTOPROVISION=true` (default for dev): if JWT has matching `dc-tenant-<x>` group, insert a `member` row on first sight. Preserves M1 behaviour.
  - `DCAPI_RBAC_AUTOPROVISION=false` (prod): 403 until an owner explicitly invites.
- **Removed from IdP.** JWT verification fails → request blocked. `role_assignments` rows remain (audit trail), can be tombstoned via `dcctl tenant remove-member`.
- **Multi-tenant user.** dcctl asks at command time which tenant to act under, or honours `--tenant` flag / `~/.dcctl/config.yaml` default.
- **Platform admin.** Asgardeo `dc-admin` group short-circuits the lookup with `effectiveRole = owner` on every scope. No `role_assignments` row needed.

### Tasks
- [ ] `db/schema.sql` + `migrate.go` — add `role_assignments` and `service_accounts` tables (idempotent ALTER patterns)
- [ ] `internal/rbac/rbac.go` — `EffectiveRole(ctx, scopeChain) Role` and `RequireRole(ctx, min Role) error` helpers
- [ ] `middleware/auth.go` — resolve principal, look up scopeless info; tenant resolution moves out of middleware into per-handler scope walk
- [ ] `middleware/serviceaccount.go` — token-based auth path (parallel to OIDC), populates the same context keys
- [ ] Apply `RequireRole` to all mutating handlers (M1 + M2 surfaces)
- [ ] `handlers/members.go` — `POST/GET/DELETE /v1/tenants/{id}/members` for owner-only membership management
- [ ] `handlers/service_accounts.go` — `POST/GET/DELETE /v1/tenants/{id}/service-accounts` (returns token exactly once on create)
- [ ] `dcctl tenant add-member|remove-member|list-members`
- [ ] `dcctl tenant create-service-account|list-service-accounts|delete-service-account`
- [ ] Integration tests: role enforcement at each verb × role matrix; service account lifecycle; auto-provision toggle
- [ ] `docs/rbac.md` — operator guide: how the model works, how M5 extends it, edge cases
- [ ] CLAUDE.md update — current state of tenancy + RBAC

### Forward compatibility with M5

When the Organisation / Subscription / Resource Group hierarchy lands (M5):
- New `scope_type` values become valid in `role_assignments`. Existing rows stay untouched.
- `RequireRole` walks a longer chain (resource → RG → subscription → tenant) instead of a 1-element chain.
- Resource tables get nullable `subscription_id` / `resource_group_id` columns; backfilled with a default subscription/RG per tenant. `tenant_id` stays as the top-level scope.
- No table renames, no data loss, no API break for M1/M2 callers.

---

## M2 — Storage & Networking

**Target**: Q3 2026 | **Status**: 🟡 Networking API live; dcctl M2 CLI shipped; VM-on-VPC gap open

### F15 — Automatic SNAT for every VPC (shipped 2026-05-11)

Every VPC now gets automatic outbound internet access. No new API surface — it is invisible to tenants.

- [x] 6 new `DCAPI_VPC_EXTERNAL_*` env vars; `ValidateF15()` fail-fast on startup
- [x] `vpc_external_ips` table: pool population, `SELECT … FOR UPDATE SKIP LOCKED` allocation, release on delete
- [x] `VpcNatGateway`, `IptablesEIP`, `IptablesSnatRule` KubeOVN CRDs provisioned per VPC (`kubeovn/nat.go`)
- [x] VPC `0.0.0.0/0` default route patched into OVN logical router (preserves existing peering routes)
- [x] `VPCNATProvisioner` interface in `providers/interface.go` (Strategy Pattern — NAT separate from NetworkProvider)
- [x] `asyncProvisionVNet` and VNet delete wired to call NAT provisioner / release EIP
- [x] Startup backfill: `runNATBackfill` goroutine provisions NAT for all ACTIVE VNets on every restart
- [x] 6 unit tests for pure functions (`kubeovn/nat_test.go`) — all PASS
- [x] 6 DB unit tests (`db/external_ip_test.go`) — correct; require `TESTCONTAINERS_RYUK_DISABLED=true` locally
- [x] 3 integration tests (`test/integration/nat_test.go`) — skip unless `DCAPI_VPC_EXTERNAL_BRIDGE` set
- [ ] **Manual E2E gate (open):** deploy to harvester-dev with F15 env vars; verify existing 3 VPCs get NAT backfilled; curl 1.1.1.1 from probe pod; expect HTTP 301

### dcctl M2 CLI (shipped 2026-05-09)

- [x] `dcctl create vnet <name> --address-space <cidr> --region <region>`
- [x] `dcctl create subnet --vnet <vnet> --name <name> --cidr <cidr>`
- [x] `dcctl create peering --vnet <vnet> --peer-vnet <peer> --name <name>`
- [x] `dcctl get vnet|subnet|peering` — detail view with --json flag
- [x] `dcctl list vnets|subnets|peerings` — table output with --json flag
- [x] `dcctl delete vnet|subnet|peering` — confirmation prompt, -y flag
- [x] `dcctl create vm` — new `--vnet` / `--subnet` flags (mutually exclusive with `--network`)
- [ ] **TODO — VM-on-VPC server gap**: `dc-api/internal/api/handlers/vm.go`
      `CreateVMRequest` struct does not yet include `vnet_id` or `subnet_id` fields.
      The CLI flags are wired and will resolve names → UUIDs, but the server
      silently ignores those fields and will reject the request because
      `network_name` is still required. To close this gap:
      1. Add `VNetID string json:"vnet_id,omitempty"` and
         `SubnetID string json:"subnet_id,omitempty"` to `CreateVMRequest`.
      2. Update `validate()` to accept either `network_name` or `vnet_id+subnet_id`.
      3. Thread `vnet_id`/`subnet_id` through to `VMSpec` and the Harvester driver
         (multus annotation on the KubeVirt VM manifest).

### Storage

- [ ] `POST /v1/volumes` — Longhorn PVC provisioning
- [ ] `POST /v1/volumes/{id}/attach` — attach to a VM (hot-plug via KubeVirt)
- [ ] `GET/DELETE /v1/volumes`
- [ ] `POST /v1/snapshots` — Longhorn VolumeSnapshot
- [ ] `POST /v1/load-balancers` — MetalLB or Harvester LB IPAddressPool allocation
- [ ] Storage quota (GiB per tenant) — add `max_storage_gb` to quotas table
- [ ] `dcctl create volume`, `dcctl attach volume`, `dcctl create lb`

### Networking — VPC / Subnet / NSG / Peering (Azure-style)

**Architectural decision (recorded 2026-04-29):** Build tenant networking on
**self-managed KubeOVN** deployed on the Harvester cluster (Model B). This is
the pragmatic path because Harvester's bundled KubeOVN VPC is still officially
labeled experimental as of v1.8.0 — we don't want our public API tied to a
vendor-experimental feature.

**Why not VyOS-as-SDN:** VyOS is a router/firewall, not an SDN. It doesn't solve
the underlying VLAN-provisioning bottleneck. AWS/Azure built proprietary SDNs
in their hypervisors over a decade — the open-source equivalent that actually
matches what they do is OVN. VyOS still has a place at the edge (managed VPN
gateways, BGP peering with corporate network) but as a tenant *resource*, not
as foundation. See conversation 2026-04-29 for the full debate.

**Why not Harvester's bundled KubeOVN VPC (Model A):**
- Harvester docs (v1.8) explicitly state "All features that use Kube-OVN are
  considered experimental" — https://docs.harvesterhci.io/v1.8/networking/kubeovn-vpc
- Tying our public VNet API stability to an experimental vendor feature is a
  bad bet
- Reassess once Harvester GAs the feature (likely v1.9 or v2.x)

**Why not standalone OVN (Model C):** Over-engineering for our scale. KubeOVN
gives us OVN with a Kubernetes-native CRD layer for free.

#### Plan

**Spike (1-2 weeks) — runs on the Harvester cluster itself, not on
`dcapi-controlplane-rke2`.** Tenant VMs are KubeVirt VMs scheduled on the
Harvester cluster — KubeOVN must live where the VMs live. The previous version
of this doc said "dcapi-controlplane-rke2"; that was wrong. KubeOVN on the
guest cluster does nothing for tenant VM networking.

Status of v1.8 reassessment (2026-05-06): Harvester v1.8.0 (released 2026-04-24)
still labels all KubeOVN sub-features experimental. The Harvester team opened
[#10415](https://github.com/harvester/harvester/issues/10415) on 2026-04-27 to
decide which sub-features to GA in v1.9 (target 2026-08-12). Three concrete
blockers are open against the bundled v1.8 feature: static IP via cloud-init
(#8844), live migration on VPC subnet (#9463), guest RKE2 cluster on overlay
(#9682). Decision stands — **stay on Model B**. Reassess at v1.9 GA.

Concrete spike steps (in order):

- [ ] **Pre-step:** Disable Harvester's bundled KubeOVN add-on in lk-dev.
      It's opt-in and off by default in v1.7.1 — confirm via
      `kubectl get addons -n harvester-system`. Disabling eliminates CRD
      version conflicts with our self-managed install.
- [ ] **Install upstream KubeOVN v1.15** on the Harvester cluster via Helm,
      configured as a **multus secondary CNI** — not primary, not replacing
      Harvester's default bridge CNI. KubeOVN runs in its own namespace; its
      pods + CRDs install side-by-side with Harvester's existing networking.
- [ ] **Manually create networking objects** (raw kubectl apply, no DC-API yet):
      one `Vpc`, two `Subnet`s in non-overlapping CIDRs (e.g. 10.0.1.0/24 and
      10.0.2.0/24), default-deny ACLs between them, and a
      `NetworkAttachmentDefinition` referencing each subnet.
- [ ] **Create two KubeVirt VMs** via raw YAML, attached to the subnets via
      multus annotations. Bypass DC-API for the spike — we want to isolate
      KubeOVN behaviour from any DC-API plumbing.
- [ ] **Verify (must all pass):**
      1. VMs boot and receive IPs from KubeOVN's IPAM.
      2. Same-subnet ping works; cross-subnet ping is blocked by default-deny ACL.
      3. Live-migrate one VM to another Harvester node — IP and connectivity persist.
      4. Existing Harvester VMs on bridge-backed NADs are unaffected (no regression).
      5. Disabling and re-enabling the KubeOVN ACL flips the cross-subnet ping
         result deterministically (proves ACL is the enforcement point).
- [ ] **Document failure modes** discovered during the spike: what broke, how
      we'd detect it in prod, what the rollback procedure is. Add to
      `docs/ops-bootstrap.md` under a new "Networking" section.

**Decision gate:** all five verifications pass → green-light DC-API
`NetworkProvider` interface and the kubeovn driver below. Anything fundamental
fails (multus webhook conflicts, KubeOVN clashes with Harvester's IPAM, live
migration breaks the overlay) → fall back to **Option C: pause M2 networking
implementation, do design-only work, reassess when Harvester v1.9 ships**.

**Spike result (2026-05-06): all 5 gates passed.** See Decision Log entry +
`docs/m2-network-api-mapping.md` for the must-implement gotchas. Proceeding
with the kubeovn driver below.

Once the spike is green:

- [x] **`NetworkProvider` interface** in `dc-api/internal/providers/` (Strategy
      Pattern, mirrors `ComputeProvider` and `ClusterProvider`)
- [x] **`kubeovn` driver** implementing `NetworkProvider` — completed 2026-05-06 (issue #149)
- [ ] **API surface** (Azure-shaped, internally maps to KubeOVN CRDs):
  - `POST /v1/vnets` → KubeOVN `Vpc`
  - `POST /v1/vnets/{id}/subnets` → KubeOVN `Subnet`
  - `POST /v1/security-groups` → KubeOVN `SecurityGroup` (ACLs)
  - `POST /v1/vnets/{id}/peerings` → KubeOVN `VpcPeering`
  - `POST /v1/nat-gateways` → KubeOVN `VpcNatGateway`
  - `POST /v1/route-tables` → KubeOVN logical router routes
- [ ] **VM/Cluster create flow** updated: accept `--vnet/--subnet` instead of
      `--network ns/nad`. Legacy `--network` flag stays for VMs that need raw
      VLAN access (escape hatch).
- [ ] **Cross-subscription peering: explicitly NOT supported.** Talking across
      subscriptions goes through API gateways or VPN. Mirrors how Azure
      originally scoped VNet peering.
- [ ] **Tenant-deployable VyOS resources (deferred to M3+):**
  - `POST /v1/vnets/{id}/vpn-gateway` — managed VyOS VM, site-to-site IPsec
  - `POST /v1/vnets/{id}/bgp-peering` — VyOS BGP terminator for corporate uplinks
  - These are *tenant resources on top of OVN*, not infrastructure

#### Tenant isolation guarantees (must hold by design)

Two VPCs belonging to different tenants — or even two VPCs in the same tenant
that have not been explicitly peered — must have **zero L3 connectivity**. The
isolation is enforced by four independent layers; defeating any one of them is
not enough to break across:

1. **Encapsulation.** Inter-VM traffic is Geneve-encapsulated by OVS on the
   Harvester host (not by the VM itself). The tunnel ID identifies the source
   VPC. The receiving host only delivers a packet to interfaces matching that
   tunnel ID. A VM cannot forge tunnel headers — it never sees them.
2. **Logical router separation.** Each VPC has its own OVN logical router. No
   default route exists between routers — packets destined for a foreign VPC
   subnet have nowhere to go.
3. **Default-deny ACLs.** OVN ACLs default-deny cross-VPC traffic. Even if a
   route were misconfigured, the ACL drops the packet at VPC ingress.
4. **DC-API peering enforcement.** `VpcPeering` is the only API that creates
   cross-VPC links. Handler validates: (a) both VPCs in same subscription,
   (b) CIDRs don't overlap, (c) audit-logs the action. **Cross-subscription
   peering: no API surface exists. Cross-tenant peering: not even possible to
   propose** — the M5 hierarchy ensures subscriptions are tenant-scoped.

CIDR overlap *between* unpeered VPCs is supported — same as AWS / Azure. Two
tenants can both use `10.0.0.0/16` and never collide because the encapsulation
layer disambiguates.

#### CIDR validation rules (must enforce in DC-API + UI)

DC-API validates every tenant CIDR against a configurable **reserved CIDR
list** before creating a VNet/Subnet. UI form fields run the same validation
client-side as a fast-feedback layer; the API is the authoritative gatekeeper.

Reserved (rejected at create time):
- **The Harvester management network** (e.g. `192.168.10.0/24` in lk-dev).
  A tenant VPC overlapping the underlay breaks NAT and routing in subtle ways
  — DNS, corporate-network reachability, audit traffic. Reject outright.
- **The Kubernetes service / pod CIDRs** of the Harvester cluster itself
  (typically `10.42.0.0/16` and `10.43.0.0/16` in RKE2).
- **Any CIDR explicitly listed in the per-region `ReservedCIDRs` config** —
  this lets each datacenter region (lk-dev, future EU, US) declare its own
  no-go ranges (corporate networks, peering ranges, etc.) without code changes.
- **Loopback (`127.0.0.0/8`), link-local (`169.254.0.0/16`), and non-RFC1918
  publics.** Tenant VPCs are RFC1918 only.

Validation enforced by:
- API handler: rejects `POST /v1/vnets` and `POST /v1/vnets/{id}/subnets` with
  HTTP 400 + clear error message ("CIDR overlaps reserved range
  `192.168.10.0/24` (datacenter management network)").
- UI: client-side check on the create-VNet form, plus the same API error
  surfaced inline if it slips through.
- CIDR overlap check at peering time (separate from create-time): two VPCs
  with identical or overlapping CIDRs cannot be peered, regardless of who
  owns them.

#### Risks

- **KubeOVN day-2 ops are on us.** Upgrades, version pinning, troubleshooting.
- **Harvester upgrades may collide with our parallel KubeOVN install.** Test
  every Harvester upgrade in a non-prod cluster first; pin both versions.
- **~10-15% network overhead** vs raw VLAN due to Geneve encapsulation. Acceptable
  for tenant workloads (AWS/Azure customers eat the same trade-off). Leave the
  legacy `--network ns/nad` path as an escape hatch for the rare workload that
  genuinely needs raw VLAN throughput.
- **MTU configuration** — underlay needs jumbo frames or accept fragmentation
  for the Geneve overhead. Document the underlay requirement.

#### Migration path: Model B → Model A (when Harvester KubeOVN GAs)

Assumes Model B has been running successfully and Harvester promotes its
bundled KubeOVN VPC to GA.

1. **Audit the API contract** — does Harvester's bundled CRD set match what we
   expose via `NetworkProvider`? Identify any fields we exposed that aren't
   in the bundled version, and fields the bundled version exposes that we don't.
2. **Side-by-side install** — Harvester's bundled KubeOVN can coexist with our
   self-managed install on a fresh cluster (different namespaces). Stand up a
   test cluster with both, prove the bundled version handles our workload set.
3. **Provider swap** — implement a second `NetworkProvider` driver
   (`kubeovn-bundled`) that talks to Harvester's CRDs directly. Same public
   API surface, different backend. Strategy Pattern earns its keep.
4. **Migration tooling** — DC-API operation that re-creates a tenant's VPC on
   the bundled stack and migrates VMs across (recreate, not in-place — VMs get
   downtime, communicate clearly).
5. **Decommission self-managed KubeOVN** once all tenants are migrated.

The whole point of putting OVN behind a `NetworkProvider` interface is that
this swap is mechanical: handlers don't change, API surface doesn't change,
only the driver changes. Same pattern that makes "swap Harvester for OpenStack"
a plausible future move.

---

## M3 — Platform Services

**Target**: Q4 2026 | **Status**: 🔵 Not Started

- [ ] `POST /v1/databases` — PostgreSQL/MySQL via CloudNativePG or Percona operator
- [ ] `POST /v1/registries` — Harbor project + robot account provisioning
- [ ] DNS record management via VyOS REST API
- [ ] TLS certificate issuance (cert-manager, Let's Encrypt or internal CA)
- [ ] Billing/chargeback API — aggregate resource-hours from audit_events

---

## M4 — Self-Service Portal & GitOps

**Target**: Q1 2027 | **Status**: 🔵 Not Started

- [ ] React web UI (calls DC-API, Asgardeo login)
- [ ] DC-API Terraform Provider — `terraform-provider-dcapi` (replaces open-cloud-datacenter modules for tenants)
- [ ] ArgoCD ApplicationSet generator — DC-API as gitops webhook source
- [ ] Grafana cost dashboard (source: billing API)

---

## DC-API Bootstrap (Cross-Cutting — must land before any new datacenter region goes live)

**Status**: 🟡 In Progress — manual run for LK dev is succeeding; modularization is next

### Context
DC-API needs to come up as part of the initial datacenter bootstrap, alongside Rancher and Harvester.
Currently we are doing this manually for LK dev. Before any new region is stood up, these steps
must be captured as Terraform in `wso2-datacenter-project` (bootstrap layer or equivalent).

### Lessons from LK dev manual run (record before they fade)
- The DC-API control-plane RKE2 cluster MUST sit on the same L2 segment as the LB
  IPPool subnet. Cluster-type Harvester LoadBalancers only allocate IPs — kube-vip
  in the guest cluster handles the VIP advertisement, so a different VLAN means
  unreachable VIPs. (See conversation 2026-04-29.)
- The mgmt clusternetwork has no DHCP for tenant VMs. Static IP must be set via
  cloud-init `bootcmd` (the `network:` key in user-data is silently ignored when
  passed inline).
- Two IPs are required from the IPPool subnet: one for the node itself
  (e.g. 192.168.10.38) and one for the LoadBalancer VIP (e.g. 192.168.10.37).

### Tasks
- [ ] New Terraform module: `wso2-datacenter-project/modules/.../dc-controlplane-bootstrap`
  Inputs: harvester namespace, mgmt CIDR + gateway, node static IP, LB VIP, Rancher creds
  Outputs: kubeconfig path, ingress hostname/IP
  Composes:
    - `harvester_network` NAD on `mgmt` clusternetwork (untagged)
    - `harvester_ippool` for the LB VIP range, scoped to the cluster's namespace/project
    - `rancher2_cluster_v2` (RKE2) using the existing `k8s-cluster` module with
      cloud-init bootcmd that pins the static IP via netplan
    - `dc-system` namespace + ConfigMap + Secrets (driven from tfvars)
    - PostgreSQL StatefulSet (Harvester CSI storage class)
    - DC-API Deployment + Service + Ingress
- [ ] Document the bootstrap sequence: Harvester → Rancher → dc-controlplane cluster → DC-API
- [ ] CI/CD: GitHub Actions workflow should target the region-specific kubeconfig (one per region)
- [ ] Replace `ops-bootstrap.md` manual steps with `terraform apply` once the module exists

---

## M5 — Organisation & Subscription Hierarchy (Azure-like)

**Target**: Q2 2027 | **Status**: 🔵 Not Started — design locked, implementation deferred

### ⚠ Critical architectural principle
**DC-API's hierarchy is OUR abstraction. It does not map 1:1 to Rancher or Harvester.**

Users see Azure-familiar concepts. What happens inside DC-API with Rancher/Harvester
is an implementation detail they never touch. If we replace Rancher tomorrow, the API
does not change. Teams never get Rancher or Harvester credentials — DC-API manages
those backends with its own admin credentials.

```
What the user sees (DC-API)          What DC-API does internally
─────────────────────────────────────────────────────────────────
Organization                    →    DC-API DB record only
  └── Subscription              →    Rancher Project (or dedicated cluster, future)
        └── Resource Group      →    Harvester namespace  (dc-<sub>-<rg>)
              └── VM            →    KubeVirt VirtualMachine CRD
              └── Cluster       →    Rancher RKE2 cluster
```

Users never see terms like "Rancher project", "Harvester namespace", or "KubeVirt".
They see Organization → Subscription → Resource Group → Resource. Familiar. Done.

### Why this exists
Currently resources belong to a flat `tenant_id`. This does not scale to multiple
teams within an org, cross-team quota aggregation, or per-environment isolation
(dev/staging/prod) within a team.

### Hierarchy
```
Organization      top-level owner (company / department)
└── Subscription  quota + billing boundary per team (≈ Azure Subscription)
    └── Resource  logical grouping within a subscription (≈ Azure Resource Group)
        Group
        └── Resource   VM, Cluster, Volume...
```

### Key design decisions (locked now, not up for debate later)
- `tenant_id` on all existing DB tables becomes `subscription_id` — migration required
- **Quota lives on Subscription**, not flat tenant. Org-level = aggregate of subscriptions.
- **Resource Groups are a metadata column** (not hard k8s namespace boundaries).
  Harvester namespaces: `dc-<subscription_slug>-<rg_slug>`.
- **RBAC is scoped to Subscription** — owner/member/viewer per subscription.
  M1.5 RBAC design is already at this level; no rework needed.
- **Rancher RBAC is never exposed** — DC-API manages Rancher with its admin token.
  Teams have DC-API roles only.
- **Organization ≠ Asgardeo org** necessarily — an Asgardeo org may contain multiple
  DC-API Organizations (e.g., different business units).
- API path: `/v1/subscriptions/{sub}/virtual-machines` (versioned break, planned)

### DB schema additions (when we get here)
```sql
CREATE TABLE organizations (
    id         TEXT PRIMARY KEY,  -- = Asgardeo org_name
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE projects (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        TEXT NOT NULL REFERENCES organizations(id),
    name          TEXT NOT NULL,
    slug          TEXT NOT NULL,  -- used as Harvester namespace prefix
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (org_id, slug)
);

CREATE TABLE resource_groups (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id),
    name       TEXT NOT NULL,   -- "prod", "staging", "dev"
    UNIQUE (project_id, name)
);
-- resources.tenant_id → resources.project_id  (migration)
-- resources.resource_group_id added
```

### Tasks (future)
- [ ] DB migration: `tenant_id` → `project_id` on resources, quotas, audit_events
- [ ] New tables: organizations, projects, resource_groups
- [ ] API: `POST /v1/projects`, `POST /v1/projects/{id}/resource-groups`
- [ ] Auth middleware: resolve org → project → role from JWT (extend M1.5 RBAC)
- [ ] Quota: aggregate at project level + org-level ceiling
- [ ] dcctl: `dcctl project create`, `dcctl project list`, `--project` flag on all commands
- [ ] Billing: cost per project (enables chargeback per team)

---

## Decision Log

| Date | Decision | Reason |
|---|---|---|
| 2026-04 | Monorepo (dc-api + dcctl in one repo) | Single source of truth; API and CLI evolve together |
| 2026-04 | 202 Accepted for create operations | VM/cluster creation is 2-5 min; sync would timeout |
| 2026-04 | DC-API owns SSH key generation | No server-stored private keys; returned once in response |
| 2026-04 | PKCE, no client secret in dcctl | CLI binaries are public; secrets would be extractable |
| 2026-04 | Rancher REST v3 directly (not TF provider) | `rancher2` provider has RKE2 cluster creation bugs |
| 2026-04 | KubeVirt CRD via k8s dynamic client | Official interface for Harvester VMs; avoids large SDK vendor |
| 2026-04 | `tenant_id` → `subscription_id` in M5 | Hierarchy locked early; Azure-like naming more familiar than "project/tenant" |
| 2026-04 | DC-API hierarchy is independent of Rancher/Harvester | Rancher concepts (project, namespace) are internal impl details; users see Org→Subscription→ResourceGroup→Resource only |
| 2026-04 | Rancher RBAC never exposed to users | DC-API holds admin credentials; all access control is DC-API's responsibility |
| 2026-04 | Resource Groups are metadata columns, not k8s namespaces | Harvester namespace = `dc-<sub>-<rg>`; avoids namespace explosion |
| 2026-04 | Org hierarchy deferred to M5 | Flat subscription model sufficient for M1 E2E; hierarchy adds complexity before value is proven |
| 2026-04 | Named VM sizes (small/medium/large/xlarge) at API level | Reduces parameterisation; mirrors AWS/Azure style; disk overridable separately |
| 2026-04 | `dcctl list` for collections, `dcctl get <id>` for single resources | Matches kubectl/az UX convention; cleaner than `get vms` vs `get vm <id>` |
| 2026-05 | M2 networking decision held at Model B after v1.8 reassessment | Harvester v1.8.0 still labels all KubeOVN sub-features experimental; #8844, #9463, #9682 are blockers for our M2 scope. Reassess at v1.9 GA (~2026-08). |
| 2026-05 | KubeOVN spike runs on the Harvester cluster, not the dcapi-controlplane-rke2 guest cluster | Tenant VMs are KubeVirt VMs scheduled on Harvester; KubeOVN must live where the VMs live. Earlier version of MILESTONES.md was incorrect on this. |
| 2026-05-06 | **M2 networking spike PASSED — all 5 gates green. Model B (self-managed upstream KubeOVN as multus secondary) is confirmed viable.** | Gate 1 (IP allocation), Gate 2 (cross-subnet ping), Gate 3 (live migration with IP/MAC preserved), Gate 4 (ACL toggle deterministic), Gate 5 (no regression on bridge VMs) all passed. Findings documented in `docs/m2-network-api-mapping.md` — must-implement gotchas (MAC pinning, CPU model for migration, preferred-not-required affinity, patch-not-delete for ACLs, phantom IPs, multus default override behavior, post-migration rebind window). Green-light to implement DC-API kubeovn driver. |
| 2026-05-06 | **KubeOVN driver (#149) completed.** VpcDns CRD probed at startup; falls back to ConfigMap DNS mode if absent. Route entries and ACL entries tagged with owner UUID for clean patch-not-delete removal. NSG and RouteTable backendUIDs encode composite keys (pipe-delimited subnet list; slash-delimited vnetUID/rtUUID). `namespaceForTenant` extracted to `providers/common` package shared by harvester and kubeovn drivers. `DCAPI_KUBEOVN_NAMESPACE` env var added (default: `kube-ovn`). GVR plurals verified on v1.15: `vpc-peerings` uses a hyphen. VpcDns record-level API not available in v1.15 — ConfigMap path used for all record operations even when VpcDns CRD is present. | Issue #150 (handlers) and #151 (integration tests) are the next steps. |
| 2026-05-11 | **F15 shipped: automatic per-VPC SNAT via KubeOVN VpcNatGateway.** Every VPC gets outbound internet automatically. EIP pool is operator-configured; allocation uses `SELECT … FOR UPDATE SKIP LOCKED` for concurrency safety. SNAT operates at VPC logical-router boundary — cluster CNI is fully opaque. Startup backfill covers pre-existing VPCs. `VPCNATProvisioner` kept separate from `NetworkProvider` (Strategy Pattern). Manual E2E gate (curl 1.1.1.1 from probe pod) is open — must run on harvester-dev before tagging M2 complete. | `DCAPI_VPC_EXTERNAL_BRIDGE` env var gates NAT provisioning; when unset the code path is fully bypassed. |

---

## Rabbit Hole Recovery Checklist

If you're deep in a debugging session and losing sight of the goal, ask:

1. **Which M1 task does this unblock?** (If none, park it as a backlog item.)
2. **Is there a simpler workaround that gets us to the next test?**
3. **Has this been caused by a TODO stub?** (Check `// TODO:` comments in provider code.)
4. **Can we mock this away for now and come back?** (Mock provider, skip the real Harvester call.)
