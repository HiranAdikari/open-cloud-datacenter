# Follow-ups

Things we've decided are worth doing but aren't blocking the current
milestone. Each entry should be self-contained enough that a fresh agent
(or you on a Monday morning) can pick it up cold.

When an item lands, delete it from this file in the same PR — don't
strike-through. Git history keeps the record.

---

## Spec-driven leverage (added 2026-05-10)

`dc-api/openapi.yaml` shipped 2026-05-09. cloud-ui already consumes it
via `openapi-typescript` + `openapi-fetch`. Three more consumers are
worth wiring up — none is urgent, all give compounding value.

(F1 shipped 2026-05-15 — dcctl now uses an oapi-codegen-generated
`dcapi.ClientWithResponses` end to end. The hand-rolled untyped
helpers (Get/Post/Delete/GetList/GetRaw and per-resource wrappers)
are deleted. Spec drift in `openapi.yaml` now breaks `go build`
instead of breaking dcctl at runtime. Regenerate the client with
`go generate ./internal/client/generated/...` from `dcctl/`.)

(F2 shipped 2026-05-15 — `dc-api/test/contract/` runs schemathesis
against an in-process dc-api with all backend providers nopped out
and testcontainers Postgres. 17 operations × ~80 cases = ~1400 test
cases per run. Pre-merge CI gate at `.github/workflows/contract.yaml`.
First run flushed out the Chi default 404 + /healthz Content-Type
divergences; both fixed in the same commit. Scope is the data-plane-light
subset of operations — networking / VM / cluster / bastion tags still
need the live integration suite.)

(F3 shipped 2026-05-15 — `openapi.yaml` is embedded via `go:embed`
and served unauthenticated. `GET /openapi.yaml` returns the raw spec
for tooling; `GET /docs` is a Redoc HTML page that renders the spec
from the same origin. The spec describes the surface but carries no
secrets, so both routes are intentionally public.)

---

## RBAC / scaling

(F4 shipped 2026-05-15 — `schema.sql` is now fully idempotent, the
resources-table sentinel and alterations slice are gone, and Migrate
runs schema.sql unconditionally on every boot. Verified twice against
the live lk-dev DB with no schema or data drift.)

---

## Networking

(F5 shipped 2026-05-15 — `peering_live_test.go` now asserts each
`Vpc.spec.staticRoutes[*].nextHopIP` is in `100.64.0.0/10`. Runs in
~38s vs the old 30-40 min ping path.)

(F6 shipped 2026-05-16 — transit /24 now comes from a DB-backed
first-unused-index allocator (`peering_transit_cidrs` table). The
SHA-256 hash stays as a fallback so peerings created pre-F6 keep
their existing localConnectIP. Verified live against harvester-dev:
first allocation lands on `100.64.0.0/24`, the row is freed on
Peering DELETE.)

---

## Auth

(F7 shipped 2026-05-16 — dc-api runs the OIDC code-with-PKCE flow
server-side against a confidential `cloud_ui_bff` Asgardeo client
and hands the browser an HttpOnly `dcapi_session` cookie. Four new
endpoints under `/v1/auth/{login,callback,logout,me}`; OIDC
middleware extended to accept the cookie alongside the Bearer
header dcctl uses. cloud-ui rewritten to drop `oidc-client-ts`
and use `/v1/auth/me` on mount. Verified end-to-end locally with
the user signing in via Asgardeo and reaching the tenant picker.
One known caveat tracked as F47 — Asgardeo's `cloud_ui_bff` access
token omits the `groups` claim despite the TF claim_configuration,
so the BFF currently seals the ID token in the session as a
workaround; F47 fixes this properly.)

### F9. cloud-ui visual polish pass

**Why:** During Chunk 2 build-out the user noted the UI works but
isn't visually polished — Fluent v9 defaults plus the prototype's
tokens get us to "functional cloud-console-shaped" but not to the
crisp Azure-Portal feel the prototype's screens promised. Worth a
focused pass once the basics (VM CRUD, networking surface, IAM)
are wired and we know which patterns recur.

**What to do (when):** after Chunks 2-5 are functionally complete,
do a focused design pass: density tightening, table row spacing,
StatusPill colour calibration vs prototype's exact swatches, empty
states with proper illustrated placeholders (the prototype has
hand-drawn art for these), drawer footer affordances, command-bar
visual weight, table hover/select states, page-header padding
consistency, and dark-mode parity audit. Probably worth a fresh
Claude Design handoff focused on these specific pain points rather
than redesigning from scratch.

**Effort:** 2-3 days for the pass + iteration.
**Risk:** Negligible — pure CSS/layout, no API changes.

### F10. VM reachability story — bastion → VPN → tunnel

**Why:** VMs created today get a real KubeOVN private IP (e.g.
`10.10.1.50`) that **isn't reachable from anywhere except other VMs
in the same VPC**. The cloud-ui shows the SSH command but operators
can't actually connect. Serial console works but isn't usable for
real work. This makes dc-api "we provisioned a VM somewhere" rather
than "we provisioned a VM you can use" — the single biggest gap
between what we offer and what a tenant actually needs.

**Three sequenced builds, smallest first:**

**Path A — Managed bastion host (M2 follow-up, ~2 days):**
A new top-level dc-api resource `Bastion`, modelled like a VM but
with a Harvester LoadBalancer-backed external IP automatically
allocated from an IPPool. Cloud-ui shows the bastion in the side
nav. SSH command displayed in the VM detail page becomes
`ssh -i web-01.pem -J ubuntu@<bastion.ip> ubuntu@10.10.1.50`.

**Path B — WireGuard VPN gateway (M3 milestone, ~5 days):**
A new `VPNGateway` resource attached to a VNet. dc-api runs a
WireGuard pod, exposes its UDP port via Harvester LB, generates
per-user peer configs (the user-facing config is shown via the
existing SecretRevealBanner pattern — config blob shown once).
Operators install WireGuard locally, paste the config, get routed
L3 access to the whole VPC. Direct `ssh ubuntu@10.10.1.50` works.

**Path C — dc-api SSH tunnel (eventual polish, ~7-10 days):**
`dcctl ssh <vm-id>` streams a TCP tunnel via dc-api → kube-apiserver
proxy → tenant proxy pod → KubeOVN → VM. No public IP needed, no
VPN client, identity bound to existing dc-api OIDC session. Mirrors
GCP IAP TCP Forwarding. Best UX but biggest build.

**Recommendation:** ship A first to unblock real use; B becomes the
"real cloud" answer once we have proper IPPool management; C is
follow-up polish.

**Path NOT taken:** assigning a public LoadBalancer IP per VM by
default (AWS-style). Cheap to build, terrible default — every VM
ends up world-exposed and security relies on NSG rules being right.
Available as an opt-in flag if we ever need it, but never default.

**Risk:** Low for A (familiar pattern, existing components). Medium
for B (key management, peer rotation). High for C (streaming TCP
through HTTP, complex to debug).

(F11 shipped — confirmed 2026-05-16. VNets list + create wizard,
VNet detail with Overview/Subnets/Peerings/Route-tables tabs (the
last tab is a deferred-to-F10 notice card, as agreed), symmetric
peerings, NSGs list + create + detail with Inbound/Outbound/Attachments
tabs all working. Private DNS is the only in-scope item still
stubbed; it stays blocked on F13 because no resolver consumes the
zones yet. Topology graph view remains deliberately out of scope.)

### F13. Private DNS UI — wire up after a resolver consumes the zones

**Why:** dc-api accepts private-dns-zone CRUD, but the data path is
half-built: when KubeOVN's VpcDns CRD is missing (current cluster
state), the driver falls back to per-zone ConfigMaps named
`dc-dns-<zone-uuid>` in the tenant namespace. **Nothing currently
reads those ConfigMaps.** No CoreDNS file-plugin is mounted to load
them; no VM has its resolver pointed at them. So creating a zone
+ records in the UI today succeeds at the API layer but produces
zero observable effect in any VM.

The full architecture (VyOS-managed gateways doing DNS for each
VPC, or installing the VpcDns CRD on KubeOVN) is the M2 networking
strategy memo's open question. Until that ships, the UI surfacing
"Private DNS zones" would let users do something that looks
functional but isn't.

**When it becomes useful:** the moment one of these paths ships:
  - VpcDns CRD installed on the KubeOVN cluster (driver auto-uses
    it; no API change needed)
  - VyOS / equivalent gateways with DNS resolver routed via the
    ConfigMaps that dc-api already produces
  - A managed resolver per VPC that reads the same ConfigMaps

**What to build:** zone list page (table with name, record count,
status, created), zone detail with a Records sub-tab. The records
editor is similar in shape to NSG rules — inline grid for
add/edit/remove, save replaces all. Endpoints
`/v1/private-dns-zones` and `/v1/private-dns-zones/{id}/records`
already exist server-side.

**Effort:** 1 day for list + zone detail with records editor.

**Risk:** Low — pure UI work once the resolver path is real. Until
then, building this would be the third "feature that looks like it
works but doesn't" pattern (after route tables and the original SPA
OIDC saga).

### F12. Route tables UI — wire up after F10 lands

**Why:** Spent ~half a day building a RouteTablesTab component that
listed route tables, edited routes inline, and managed
subnet-to-route-table associations. Then realised it has no
purpose today: the spec itself says "per-subnet routing is
informational in M2 — all routes apply at the VPC level". Plus
there's nothing meaningful to route TO yet — no managed firewall,
no VPN gateway (that's F10), no on-prem peer. Reverted before
committing.

**When it becomes useful:** the moment F10 ships a managed
bastion / VPN gateway, route tables suddenly matter — tenants
need to direct `0.0.0.0/0` (or specific CIDRs) to those
gateways. Also when M2.5 ships per-subnet OVN policy routes the
"informational" caveat goes away.

**What to build:** the design from the reverted draft was
sound — list of route tables on VNet detail's Route tables tab,
click → drawer with two sections (Routes editor + Associations
manager). Routes use a small grid (name / destination CIDR /
next-hop type / next-hop IP / remove) with conditional fields
based on next-hop type. Associations are a dropdown of subnets
in the VNet with a remove kebab. The PUT replaces all routes;
associations are POST/DELETE separately. Recover from git
history when ready: the file lived at
`cloud-ui/src/components/RouteTablesTab.tsx` in the work-in-
progress before commit `340f5e6`.

**Effort:** ~1 day to revive the draft, fix the type errors
(the GET on associations endpoint isn't in the OpenAPI spec —
add it server-side first), polish, and ship.

### F8. Import dc-apiv2 + dccli Asgardeo apps into TF

**Why:** Both apps were created manually following
docs/asgardeo-setup.md before TF was introduced. Their consumer keys
are referenced as `oidc_audience` in
`environments/lk-dev/02-dc-controlplane-services/dc-api.tf` as
**hardcoded strings** with a TODO comment, because there's no TF
resource to read the value from. If anyone rotates either app's
client credentials in Asgardeo, dc-api silently 401s every CLI call
until the hardcoded value is bumped.

**What to do:**
1. In `03-asgardeo-auth/main.tf`, declare both apps as
   `asgardeo_application` resources (mirror the working `cloud_ui`
   block — both are non-public clients with PKCE).
2. Run `terraform import asgardeo_application.dc_apiv2 7c23dff8-...`
   and `terraform import asgardeo_application.dccli 8f6cd564-...` so
   TF adopts the existing apps without recreating them. Verify the
   plan after import is empty.
3. Add outputs for both client_ids in `outputs.tf`:
   `dc_apiv2_client_id`, `dccli_client_id`.
4. Replace the two hardcoded strings in
   `02-dc-controlplane-services/dc-api.tf` with
   `data.terraform_remote_state.asgardeo_auth.outputs.dc_apiv2_client_id`
   and `... .dccli_client_id`.
5. `terraform plan` in `02-dc-controlplane-services` should show zero
   changes (same string values, just sourced from state instead of
   inline).

**Effort:** 1-2 hours. The hard part is making sure the imported
state matches what TF would create — small drifts (e.g. consent
config) might force in-place updates on first apply. Inspect the
plan carefully.

**Risk:** Low if done carefully. Worst case a stray plan recreates an
app and rotates its client_id, breaking dcctl until env is updated.
Read the plan; don't apply blind.

### F22. Dedicated VLAN for VPC external network

**Why:** F15 currently puts the `ovn-vpc-external-network` Subnet
on the same VLAN (`0` = untagged) as the management network. That
means OVN's logical-router localnet port AND VpcNatGateway pods
share the L2 broadcast domain with Harvester management VIPs,
Rancher control plane, and host kubelets. F21 prevents tenant
bridge VMs from joining, but F22 is the cleaner long-term fix:
**isolate VPC external IPAM onto a dedicated VLAN.**

Currently allocated by KubeOVN on `192.168.10.0/24`:
- `.1` = current VpcNatGateway pod external NIC (from
  vnet-hiran-test-f15-net)
- `.2` = current IptablesEIP for same VPC

These coexist with `.6` (Harvester VIP), `.35`/`.37` (other
VIPs), `.15`/`.17` (host nodes), etc. on a single broadcast
domain. Any L2 ARP misbehaviour bleeds across.

**What to do:**
1. Network team allocates a new VLAN (e.g., VLAN 701) trunked
   to all Harvester nodes, with its own CIDR (e.g.,
   `192.168.20.0/24`).
2. Update F15 config: `DCAPI_VPC_EXTERNAL_VLAN_ID=701`,
   `DCAPI_VPC_EXTERNAL_CIDR=192.168.20.0/24`,
   `DCAPI_VPC_EXTERNAL_GATEWAY=192.168.20.1` (whatever).
3. Tear down + re-create the F15 bootstrap on the new VLAN.
4. Existing VPCs' NAT resources will need to be recreated
   (their EIPs are on the old VLAN); a delete-then-recreate
   cycle via dc-api should suffice.

**Effort:** 1 day end-to-end including network coordination.

**Risk:** Medium — touches the live SNAT path. Stage carefully.

### F23. Investigate DHCP behaviour on `192.168.10.0/24`

**Why:** Open question from the 2026-05-11 evening incident: does
the upstream DHCP server on the office LAN do ARP-probe before
handing out a lease? If yes, the bridge-VM incident was caused by
something else (likely the F21 flow reconverge). If no, then any
future VM that's allowed to DHCP on this LAN could grab a
kube-vip-served VIP. Worth a 30-min tcpdump capture during a
controlled lease-acquire to know which mitigation is mandatory
vs nice-to-have.

**Effort:** 30 min. tcpdump on `mgmt-bo` while a sacrificial
client requests DHCP.

**Risk:** Zero (read-only diagnostic).

(F24 shipped 2026-05-15 — `mustCreateActiveVNet`'s `t.Cleanup` now
calls `SweepKubeOVNVPC` after the API DELETE, force-removing the
kubeovn Vpc + its Subnets even when the API path times out.
Operator-runnable `TestZombieSweep` (gated by `DCAPI_ZOMBIE_SWEEP=1`)
purges any leftover debris by tenant-label prefix. Verified live:
cleared 11 zombies in 13s on first run.)

### F27. kube-ovn burst throughput — bottleneck is NOT CPU; needs proper measurement spike

**Why:** Surfaced 2026-05-12 during F20 integration test runs.
Eleven integration tests hit kubeovn in parallel (each creating
+ deleting a VPC, subnet, NAT gateway, and DNS deployment) and
3 of them consistently timed out at the 3-min `WaitSubnetGone`
helper — *even after* F26 made the per-VPC pod teardown
deterministic. Symptom is "subnet stuck DELETING for > 3 min
under burst load." Same tests sometimes pass at 60s under low
load. Sequential `-parallel 1` runs hit the same wall on a
heavily-used cluster.

**Initial guess was CPU-bound. Direct measurement disproves
that.** `/sys/fs/cgroup/cpu.stat` on both `kube-ovn-controller`
and `ovn-central` shows:
- `nr_throttled` near zero across multi-day pod lifetimes
- `throttled_usec` totals well under 1 second
- Instantaneous CPU usage 1-8% of limits

So bumping CPU/memory limits, or scaling replicas, **won't fix
this**. The bottleneck is somewhere else.

**Most likely actual bottlenecks (need a spike to confirm):**

1. **`kube-ovn-controller` workqueue serialization.** Even with
   multiple workers, items keyed on the same resource (e.g.
   "this Subnet") run serially. Bulk operations on related
   resources don't parallelize well.
2. **`ovn-northd` logical-flow recomputation.** Single-threaded
   compute; low instantaneous CPU per cycle but each subnet
   add/remove triggers a full reconvergence cycle whose wall
   time grows with the size of the OVN northbound DB.
3. **Finalizer-driven cleanup round-trips.** Each
   delete-with-finalizer requires multiple round-trips through
   controller → ovsdb-server → ovn-sb → kube-apiserver → etcd
   before the finalizer clears. Cumulative latency, not CPU.

**v1.15.4 panic worth noting:** During this investigation we
also hit a `kube-ovn-controller` nil-pointer crash in
`controller/subnet.go:1885` (`isOvnSubnet`) when ~24 orphaned
`ips.kubeovn.io` CRs referenced deleted subnets. Workaround:
strip the `kubeovn.io/kube-ovn-controller` finalizer on those
CRs and delete them. Possibly an upstream bug to file (or
fixed in a later v1.15.x patch — worth a check before our
next k8s upgrade).

**Real-world impact:** At realistic LK scale (20-30 tenants ×
5-8 VPCs = 100-240 VPCs total), steady-state is fine. **Burst
operations** — a tenant creating 10 VPCs in a script, an
operator-side cluster reseed, a load test, a multi-tenant
deploy automation — will hit the same wall the integration
tests hit.

**What to do (in order):**

1. **Proper measurement spike first.** Restart `kube-ovn-controller`
   to a clean cgroup, snapshot `cpu.stat` + `proc/$pid/status` on
   `kube-ovn-controller` AND `ovn-northd`, fire a known-size burst
   (e.g. 20 VPC creates via dcctl), snapshot again. Compute deltas.
   Identify which component(s) actually saturate. Without this we're
   guessing.
2. Possible Helm-side changes once the bottleneck is identified:
   - `--worker-num=10` on `kube-ovn-controller` if workqueue is the choke
   - `ovn-central` Raft HA if ovn-northd compute is the choke (HA spreads
     the read side; writes still serialize via Raft, but it gives us 3
     hot-spare northds that can leader-elect on failure)
   - Resource bumps only if measurement actually shows saturation
3. **dc-api-side mitigation (independently useful):** per-tenant rate-limit
   on concurrent VPC mutations — block any tenant from having more than
   (e.g.) 3 simultaneous VPC create-or-delete operations in flight.
   Smooths burst into kubeovn from our side; an "abusive" client can't
   take down the cluster. Goes in the VNet + Subnet handlers as a
   semaphore keyed by tenant_id.

**Effort:** Measurement spike: half-day. Helm tuning: depends on
findings. dc-api rate-limit: half-day, purely additive, can ship
independently.

**Risk:** Measurement is read-only. Helm-side changes touch shared
Harvester infra — need a maintenance window. dc-api-side rate
limit is purely additive.

**Architectural levers — only relevant if measurement shows
sustained saturation at LK scale (not expected at 100-240 VPCs):**

- **kube-ovn distributed gateway mode for F15** — eliminates the
  per-VPC NAT gateway pod by doing host-level SNAT on each node.
  Roughly halves the per-VPC pod count and removes a chunk of
  per-VPC OVN topology. Requires changing kube-ovn's
  `--enable-eip-snat` pattern.
- **Shared CoreDNS pod for F20** — one (or HA pair) CoreDNS pod
  with Multus NICs into every tenant VPC. Constant memory cost
  regardless of tenant count. Tradeoff: single point of DNS
  failure across all tenants; per-tenant Corefile customization
  gets harder.
- **Opt-in DNS** — only tenants who explicitly request custom
  DNS get a per-VPC CoreDNS; the rest use a shared cluster
  default. Best ops/UX balance if customization demand is low.

These are 3-5 day spikes each. **Don't pre-implement** — wait
until measurement shows the bottleneck is total resource
count rather than reconciliation throughput.

---


(F30 resolved 2026-05-16 — closed out. The `Unexpected Identity
Change` surface turned out to be a one-shot edge case that no
longer reproduces; the dc-webhooks TF state has been re-applying
cleanly. No code change needed — striking from the open list.)

(F35 shipped 2026-05-16 — CLAUDE.md's "Before pushing changes"
section now requires a spec-diff against a known-working reference
for any PR that generates a Kubernetes CR mirroring a live object.
Every non-empty hunk needs a one-line justification in the PR
description. Five-minute discipline check; would have caught all
four F32 chunk-2 bugs in a single review pass.)

(F39 shipped 2026-05-15 — `pickProgressMessage` in rancher/client.go
prefers Reconciling=True, falls back to first non-True message,
skips Stalled. The reconciler persists message-only updates so
`Cluster.message` surfaces "waiting for viable init node",
"configuring control plane", etc. during PENDING with no status
flip. OpenAPI Cluster.message documents per-status semantics.)

### F42. IAP-style identity-tunneled VM access (F10 path C) — parked

**Why:** Captured the design + effort so when we revisit "real cloud"
VM reachability we don't re-derive it. Not a first-cut item; path A
(bastion) is doing the job today.

**What it would replace:** SSH-key-shaped bastion access with
identity-tunneled WebSocket access — `dcctl ssh <vm-id>` opens a
WSS to dc-api, OIDC-bearer-auth'd, no public IP, no bastion VM,
no SSH keys to share with teammates. Mirrors GCP IAP TCP Forwarding,
AWS SSM Session Manager, Cloudflare Tunnel.

**Architecture (3 layers, mirrors F15/F20's per-VPC infra pattern):**

1. Per-VPC `tunnel-proxy` pod — Multus secondary NIC on the tenant
   OVN subnet. Accepts HTTPS connections carrying an HMAC-signed
   JWT (target_ip + target_port + expiry), opens a TCP socket to
   the target, byte-copies. ~50 MB pod, alongside F15 NAT-gw and
   F20 CoreDNS.

2. dc-api WebSocket endpoint `WS /v1/virtual-machines/{id}/ssh-tunnel`
   — OIDC auth + tenant/role authz on the VM, mints the per-session
   JWT, bridges the WSS stream to the per-VPC proxy. Same pattern
   Kubernetes apiserver uses for `kubectl exec`.

3. `dcctl ssh <vm-id>` — opens the WS, exec's `ssh` with
   `ProxyCommand=` pointing at stdin/stdout passthrough mode.

**Effort breakdown (~8-10 days for v1):**

- Phase 1: tunnel-proxy pod + image + per-VPC deploy logic — 2d
- Phase 2: dc-api WS endpoint + JWT mint/verify + bridge — 2d
- Phase 3: dcctl `ssh` / `ssh-tunnel` commands — 2d
- Phase 4: audit (SessionLog table) + cloud-ui session history — 2d

**Replication confidence:** High. None of the components are
novel — Cloudflare Tunnel, Tailscale `tsnet`, AWS SSM Session
Manager, kubectl exec all use variants of the same WSS+HMAC+TCP
proxy pattern.

**Wins over Path A (bastion):** zero external attack surface,
no SSH-key sharing per tenant, audit trail per session, revoke a
user's access at the IAM layer (no key rotation needed), no
standing LB IP per VPC.

**Costs vs Path A:** ~4x more code, same standing-pod count per
VPC, no native `ssh` UX (need `ProxyCommand=` glue). Per-port
policy + multi-stream multiplexing punted out of v1.

**Triggers to revisit:**
- Tenants complain about managing bastion SSH keys
- Compliance / security review wants no SSH port reachable on the LAN
- We need per-session audit for SOC2-style controls
- A tenant wants to revoke a specific user's VM access without
  rotating every VM's key

**Effort to keep this entry useful:** the design above stands.
When triggering, write Phase 1 first against a single test VPC,
prove the byte-copy works, then build the WSS endpoint.

(F43 shipped 2026-05-15 — `forceRemoveNADFinalizerIfStuck` polls
the NAD for 15s after Subnet teardown, then patches finalizers to
`[]` under three-layer safety: call-chain delete intent +
`dc-api/managed=true` ownership label + scan all pods for any
Multus annotation that still references the NAD.)

### F47. Asgardeo cloud_ui_bff — emit `groups` in access token, drop ID-token swap

**Why:** During F7 chunk 1 local verification on 2026-05-16 the BFF
callback handler logged both tokens Asgardeo issues to
`cloud_ui_bff`. The `groups` claim is present in the ID token but
**absent from the access token**, even though
`claim_configuration.requested_claims` in TF marks `groups` as
mandatory. By contrast, the legacy `dc-apiv2` app (manually
created pre-TF) DOES include `groups` in its access token. So the
omission is per-app Asgardeo behaviour, not a hard limitation.

The current workaround in `internal/api/auth/handlers.go`
(`HandleCallback`) seals the **ID token** into the dcapi_session
cookie instead of the OAuth access token. Both are JWTs from the
same issuer; the auth middleware verifies signature + audience +
group→tenant identically, so it works. But semantically the BFF
should be storing an access token (the token meant for API
access), and dcctl-style integrations DO store access tokens — so
keeping these two paths divergent is a small landmine.

**What to do:**
1. Reproduce the per-app difference. Compare the Asgardeo console
   view of `dc-apiv2` and `cloud_ui_bff` side-by-side under
   *Token Issuer*, *Claims*, and *User Attributes* until the
   knob that includes `groups` in access tokens surfaces.
2. Add that knob to the `cloud_ui_bff` resource in
   `environments/lk-dev/03-asgardeo-auth/main.tf`. The
   `terraform-provider-asgardeo` source at
   `/Users/hiranadikari/Documents/wso2/dc/terraform-provider-asgardeo/`
   is the contract — if the field doesn't exist yet, add it to
   the provider first (provider-side change) and bump the
   provider version pin.
3. Verify Asgardeo issues `groups` in the new access token (curl
   the issuer's token endpoint with client_credentials or do
   another sign-in dance and decode the JWT).
4. Revert the ID-token swap in handlers.go — change
   `AccessToken: rawIDToken` back to `AccessToken: token.AccessToken`,
   drop the workaround TODO comment.

**Effort:** ½ day, most of it spent identifying the Asgardeo knob.

**Risk:** Low. The current workaround is functional; this is
hygiene.

### F46. Modularise dc-api Asgardeo wiring into the OCD module

**Why:** F7 chunk 3 put the BFF Asgardeo client in
`environments/lk-dev/03-asgardeo-auth/main.tf` (good — it sits next
to the existing `cloud_ui` SPA app and the Rancher SSO module) but
the consumer-side plumbing — adding `bff_*` variables to the OCD
`dc-controlplane-services` module, projecting them into the dc-api
Secret + ConfigMap + Deployment env, and adding the BFF client_id
to `oidc_audience` — currently lives in the per-environment layer.
Replicating that into a second region (lk, eu, us…) means copy-
pasting non-trivial Terraform across environments.

**What to do:**
1. Extract the BFF-input variables (`bff_client_id`,
   `bff_client_secret`, `bff_session_secret`,
   `bff_redirect_url`, `bff_post_login_redirect`,
   `bff_post_logout_redirect`, `bff_cookie_domain`,
   `bff_cookie_secure`) into a dedicated sub-module under
   `open-cloud-datacenter/modules/management/asgardeo-bff/` (or
   similar) that owns the Secret/ConfigMap/env wiring.
2. Have `dc-controlplane-services` consume it as a child module
   so the env layer just passes the BFF outputs straight in,
   without rewriting the projection logic.
3. Bump the OCD module SemVer tag and the consumer pin per the
   `wso2-datacenter-project` CLAUDE.md SemVer policy.
4. New regions then add a single module block, not 8 inputs +
   3 resource projections.

**Effort:** ~½ day. Pure TF restructuring; live cluster state is
already correct.

**Risk:** Low. Refactor preserves the same Secret/ConfigMap/env
projections; `terraform plan` after the change should be a no-op
on lk-dev.

### F57. Tighter per-KeyVaultInstance dc-api scoping

**Why:** F51 (just shipped) gives dc-api a per-tenant scoped token —
big improvement on root, but within the tenant's OpenBao Raft cluster
the token can CRUD any vault. A dc-api code-bug exploited by a user
authenticated to vault A could be made to read/write vault B in the
same tenant.

Cross-tenant attack is already blocked (each tenant has its own
OpenBao cluster + own Secret + RBAC on the dc-api ServiceAccount).
This follow-up is intra-tenant only.

**What to do:** Mint a per-KeyVaultInstance token at Instance-create
time in the KVI Instance reconciler. Policy template:
```hcl
path "tenants/<tenant-uuid>/<vault-uuid>/data/*"     { capabilities = [...] }
path "tenants/<tenant-uuid>/<vault-uuid>/metadata/*" { capabilities = [...] }
... (same shape as F51, but with both UUIDs hardcoded)
```
Store in the per-KVI Secret (already exists for AppRole creds — just
add a `dcapi_token` field). dc-api's `ReadDCAPIToken(tenantSlug, vaultID)`
takes the vault id and reads the per-vault token.

**Cost:**
- 1 extra Secret-read per request (cache-able via F52)
- N more Secrets per tenant (one per vault)
- Policy template per vault (small OpenBao write per Instance reconcile)

**Effort:** ~2-3h. Mechanical extension of F51's pattern.

**Risk:** Low if landed after F52 (token cache). Without the cache,
secret-CRUD-heavy workloads pay the extra K8s GET on every call.

**When to do:** After F49 (federation) design has settled. Federation
might supersede this entirely (per-request, per-user tokens) so we
don't want to invest in F57 if F49 is imminent.

### F56. OCD — bundle dc-operator modules into one `dc-operators` umbrella

**Why:** Today each operator that runs on the workload cluster
(`dc-webhook`, `keyvault-operator`, and any future per-managed-service
controller) lives as a separate OCD module. The consumer has to
remember to call each one — miss any and the cloud bootstraps but
features silently fail to function (e.g. tenants register fine but
KV create stays PENDING forever because the KVI controller isn't
deployed). This is "make-the-easy-thing-be-right" hygiene.

**What to do:** Add a new umbrella module
`open-cloud-datacenter/modules/management/dc-operators/` that
instantiates every workload-cluster operator as child modules.
Inputs roll up: image refs per operator, namespaces, shared GHCR
pull-cred, log_level. Consumers call ONE module:
```hcl
module "dc_operators" {
  source = "../modules/.../management/dc-operators"
  ghcr_pat = var.ghcr_pat
  ...
}
```
and never have to know that webhook/KVI/etc are separate.

Each operator module continues to exist underneath so advanced
consumers can still mix-and-match if they want (e.g. for a region
that doesn't run a Key Vault story yet). The umbrella is a thin
wrapper, not a replacement.

When the umbrella ships, the consumer side becomes a one-line
upgrade: replace the per-operator module blocks in
`02-dc-operators` with a single umbrella block.

**Effort:** ~2h. Pure restructuring; no per-operator code change.

**Risk:** Low. Backward-compat retained (per-operator modules still
exist). Existing consumer calls keep working until they choose to
migrate.

### F54. KVI operator — durable audit log streaming

**Why:** Step 8 enables OpenBao's file audit device, but the log lives
in an emptyDir mount inside each pod. On any pod restart (rolling
update, eviction, host reboot) the file is GONE. Audit logs are the
exact thing you want to survive incidents, so emptyDir is the wrong
storage class.

**What to do:**
1. Stream the file via a sidecar: filebeat / promtail / fluent-bit
   tails `/openbao/audit/audit.log` and ships to Loki / Elasticsearch
   / S3 / a SIEM. Sidecar is in the same pod, shares the audit
   emptyDir read-only, no extra OpenBao plumbing needed.
2. Or switch from `audit "file"` to `audit "socket"` and run a
   tiny TCP receiver (logstash, vector, syslog-ng) at the cluster
   edge. Avoids on-disk persistence on the OpenBao pod entirely.
3. Or for the simplest interim: switch the audit emptyDir to a
   per-pod PVC. Survives restarts, doesn't survive PVC deletion
   (which happens on Backend delete by design — that's correct).

**Effort:** ~½ day for a filebeat sidecar; ~1 day for socket-based
shipping with a receiver Service.

**Risk:** Low. The audit log is append-only and idempotent; the
sidecar / receiver can be added without touching OpenBao at all.

### F55. KVI operator — managed rolling restart on HCL config change

**Why:** Step 8 ships an `hcl-checksum` pod-template annotation so
StatefulSet diff includes the change, but our SS uses
`updateStrategy: OnDelete` (deliberate, for Raft safety). Pods
don't auto-roll. Verifying Step 8 on the live cluster required
manually `kubectl delete pod` on each in turn.

**What to do:** In the Backend reconciler, after applyChildren, if
the existing pod's `keyvault.opencloud.wso2.com/hcl-checksum`
annotation differs from the StatefulSet spec template's checksum,
delete pods one at a time (oldest first), waiting for each new
pod to become Ready AND join the Raft cluster before deleting
the next. Skip the leader until last, so re-election happens
once at the very end. Bounded by Backend phase=Provisioning
while in flight so the user sees the rollout in `dcctl keyvault
get`.

**Effort:** 2-3h including a unit test for the leader-last
ordering.

**Risk:** Medium. Touching the leader pod is the moment of
truth — bad ordering could split-brain or cause data loss. Must
verify the new leader is fully caught up before deleting the
previous one. The Raft cluster handles single-node rotation
fine in practice, but the operator code has to be careful.

### F53. Integration tests leak KV mounts + KVI Instance CRs on harvester-dev

**Why:** After the F50 integration test run, `bao secrets list` on
the per-tenant OpenBao showed many leaked mounts at
`tenants/<tenant-uuid>/<vault-uuid>` paths, and
`kubectl get keyvaultinstance -A` showed ~16 leftover `kv-*` CRs
in `dc-kv-demo-default`. The test teardown should have removed
these on `t.Cleanup`. Two likely causes:
1. Teardown deletes the KVI CR but the operator's finalizer doesn't
   complete in time → CR is gone from the API server's view but the
   mount is orphaned (or vice versa).
2. Teardown is per-test but several tests share the same vault and
   only the last cleanup runs.

**What to do:**
1. Audit `test/integration/keyvault_secrets_test.go` cleanup ordering
   — every put should be paired with a delete (or the whole vault
   should be torn down at the end of the parent test, not per-sub-test).
2. Add a sweeper at the top of the test file that, on first run,
   lists every `kv-*` KVI CR with a `test-` prefix label and deletes
   them. Bounded blast — only touches things tagged as test fixtures.
3. Consider a cluster-wide sweep job (`make clean-test-fixtures`)
   that operators can run manually if test runs are interrupted.
4. Inspect OpenBao directly: bao secrets list, find mounts under
   `tenants/<uuid>/` whose UUID doesn't match any KVI CR — those are
   orphans from the finalizer race; need a one-shot manual cleanup.

**Effort:** ~½ day if it turns out to be #1 (sweeper). More if the
finalizer race needs fixing in the operator itself.

**Risk:** Low. The leftovers don't affect prod tenants (the test
tenant slug is well-isolated), but they pollute the OpenBao
audit log and make manual inspection noisier. Surfaced 2026-05-22.

### F51. Key Vault — dc-api should use a scoped policy token, not root

**Why:** F50 shipped secret CRUD by having dc-api read the per-tenant
OpenBao root token from `kvb-<tenant>-keys` and present it as
`X-Vault-Token` on every proxied request. The token works because
it is god-mode inside OpenBao — but that's also the problem. Any
auth-bypass / SSRF / handler-bug in dc-api would let an attacker
mint arbitrary tokens, rekey the cluster, drop other tenants'
mounts, exfiltrate the unseal keys. The blast radius is the whole
backend, not just our secret CRUD surface.

**What to do:**
1. KVI Backend reconciler, after `sys/init` + unseal completes,
   mints a `dc-api-admin` policy token with this policy:
     ```
     path "tenants/+/+/data/*"     { capabilities = ["create","read","update","delete"] }
     path "tenants/+/+/metadata/*" { capabilities = ["read","list","delete"] }
     path "tenants/+/+/config"     { capabilities = ["read","update"] }
     ```
   No `sys/*`, no `auth/*`, no `pki/*`. Stores it in a separate
   Secret `kvb-<tenant>-dcapi-token` (or as a second key in the
   existing keys Secret).
2. dc-api's `ReadRootToken` becomes `ReadDCAPIToken`, reads the
   scoped token instead.
3. Root token stays in `kvb-<tenant>-keys` for break-glass + Backend
   rotation; never used in normal request paths.
4. Add a periodic-rotation reconcile loop that re-mints the
   dc-api-admin token monthly (TTL ~31 days, refreshed at 24-day
   mark) so a leaked token has bounded blast.

**Effort:** ~½ day. Operator-side: add the mint step after init,
add the rotate reconciler. dc-api-side: change one helper name +
one Secret key reference.

**Risk:** Low if shipped after F50 stabilises. Backward compat:
reconciler should mint the token even if the Backend already
existed pre-F51 (idempotent — check Secret, mint if missing).

### F52. Key Vault — cache the OpenBao token per tenant in dc-api

**Why:** Every secret-CRUD API call costs one K8s API GET on the
`kvb-<tenant>-keys` Secret. The cloud-ui Secrets-tab paginating
500 secrets at 100/page = 5 list calls + 500 metadata fetches +
N value reads, each of which currently re-reads the K8s Secret.
Unnecessary load on K8s API server, ~10ms latency per request.

**What to do:** Add an in-memory map `tenantSlug → (token, expiresAt)`
in `internal/providers/kvi/client.go`. 5-minute TTL. On cache miss,
read from K8s and store. Invalidation: if any OpenBao call returns
403 (token expired/revoked), evict the entry and retry once with
a fresh token.

**Effort:** ~1h including a unit test.

**Risk:** Trivial. Worst case: a 5-min window after KVI rotates
the dc-api token (F51) where dc-api still uses the old one — the
403-and-retry path handles it.

### F50. Key Vault — human secret CRUD via dc-api/dcctl/UI

**Why:** M3 chunk 9 shipped vault *lifecycle* (create/get/delete the
vault, retrieve workload AppRole credentials). It did NOT ship a way
for humans to put / list / get / delete the actual secrets inside
a vault without bao. That breaks the "abstract the backend" promise
— the user creates a vault via dcctl, gets AppRole creds, then has
to install bao CLI, configure BAO_ADDR, login with the AppRole, and
issue `bao kv put` to store anything. That's worse UX than Azure CLI
(`az keyvault secret set --vault X --name Y --value Z`).

**What to do:**

1. **dc-api**: four new handlers under
   `/v1/tenants/{tid}/projects/{pid}/keyvaults/{id}/secrets`:
     - `PUT  /{key}`  — body `{value: "...", metadata?: {...}}`
     - `GET  /{key}`  — returns `{value, version, metadata}`
     - `GET  /`       — list keys (paginated)
     - `DELETE /{key}` — soft-delete (KV-v2 honors the vault's
                         soft_delete_days)
   The handler uses an **admin token derived from the per-Backend
   root_token** (stored in `kvb-<tenant>-keys` Secret today) — NOT
   the user's AppRole — so the AppRole stays runtime-only. RBAC
   gate is the standard `RequireRole(Member)` on the project scope
   (member can read; owner can write/delete; viewer can list keys
   but not values).

2. **dcctl**: `dcctl keyvault secret {put,get,list,delete}` as the
   `az keyvault secret ...` analog. `put` accepts `--value <v>`,
   `--from-file <path>`, or stdin. `get` honours `--json`,
   `--field=value` for shell embedding.

3. **cloud-ui**: a "Secrets" tab on `KeyVaultDetailPage` — Fluent
   `TabList` next to "Overview" + "Access". Inside: simple table
   with add/edit/delete + a reveal-value modal that copies to
   clipboard. Same shown-once-ish vibe per value reveal but the
   user can re-reveal anytime (it's their secret).

4. **Documentation**: the consumer-side runbook needs to flip
   from "bao kv put" examples to "dcctl keyvault secret put" / UI
   screenshots. The bao-direct path stays in the docs as
   "advanced / direct backend access for migration scenarios."

**Effort:** ~1 day total. Handlers ~3h (mostly a thin HTTP proxy
around OpenBao KV-v2 endpoints), dcctl ~2h, UI ~3h, integration
tests ~1h.

**Risk:** Low. KV-v2 API is stable; we're just exposing it through
our own auth. The RBAC mapping is the only real decision —
default to "member can read values, owner can write/delete" with
the caveat that *viewer* listing key NAMES is fine (no value
exposure).

**Why we missed this:** Chunk 9's framing was "wire dc-api ↔ KVI
operator end-to-end" which read as "vault lifecycle". Secret
contents got mentally lumped into "the workload does that via
AppRole" — true for workloads, false for humans. Flagged 2026-05-22
during cloud-ui design walkthrough.

### F49. Key Vault — federated identity (Azure-KV-style RBAC)

**Why:** The current AppRole model is the AWS-access-keys / Azure-SP-
client-secret pattern: dc-api mints `role_id + secret_id`, shows the
secret_id ONCE, the user copies it into their workload, the static
credential lives forever in their config. Compared with Azure KV +
managed-identity (where the workload's AAD JWT *is* the credential
and you just grant `principal → get/list/put/delete`), our model
trades operator simplicity today for credential-rotation pain
forever.

The AppRole pattern exists because tenant workloads run on tenant
RKE2 clusters that don't share an identity provider with OpenBao,
so federation isn't wired. Long-term we want to eliminate the static
secret entirely.

**What to do (sketch — needs real design):**
1. **OpenBao `kubernetes` auth method, one per tenant RKE2 cluster.**
   When a tenant cluster comes up, KVI configures OpenBao to trust
   that cluster's SA-token issuer. Workload pods with a SA token
   exchange it for an OpenBao token bound to the SA principal.
2. **OpenBao `jwt` / OIDC auth method, tied to Asgardeo.** Human
   users (dcctl, cloud-ui, terraform) authenticate via Asgardeo
   and get an OpenBao token bound to their Asgardeo subject.
3. **dc-api exposes a policy API**, not a credentials API:
   `POST .../keyvaults/{id}/policies` with `{ principal, paths,
   capabilities }`. Mirrors Azure KV's access-policy / Azure RBAC
   model. The shown-once `/credentials` endpoint then disappears
   (or becomes the "give me a fresh AppRole" fallback for cases
   where federation can't reach — e.g. external SaaS callers).
4. **UI flips from "credentials modal" to "access policy editor"** —
   list of `(principal, paths, capabilities)` rows, add/remove
   buttons. No more shown-once banners.

**Effort:** ~2 sprints. Operator work (per-cluster auth method
configuration, lifecycle on cluster create/delete) + dc-api API
surface + UI rewrite.

**Risk:** Medium. Cross-cluster trust is fiddly. Need to handle:
SA-token issuer rotation, tenant cluster deletion (revoke trust),
multi-cluster naming collisions. AppRole stays as fallback for
external callers and for cases where the workload can't expose
a SA token to dc-api's OpenBao.

**Why we're not doing it now:** Spike + chunk 9 was about proving
the operator + dc-api + dcctl + cloud-ui chain end-to-end. AppRole
is the simplest cred-issuance shape that lets us ship that today.
Federation is the obvious second pass.

### F58. KVI reconciler — bounded RequeueAfter on transient errors

**Why:** During C1 live e2e the operator hit two RBAC gaps in a row.
After each fix the controller stayed in `Failed` for minutes because
controller-runtime's default rate-limiter exponentially backs off
(5ms → 16min cap). Operators ended up touching an annotation on the
CR to force a fresh reconcile event — that's a debug hack, not an
operational pattern.

**What to do:** In `crds/keyvault/internal/controller/keyvaultbackend_controller.go`
(and the Instance reconciler), classify errors:
- Transient cluster-side (RBAC, namespace not found, conflict,
  API-server timeout) → return `ctrl.Result{RequeueAfter: 15 * time.Second}, nil`
  AFTER setting Phase=Failed with the message. The nil error stops
  controller-runtime from applying its own backoff on top.
- Permanent spec errors (invalid CRD, missing required external
  resource user must fix) → return `ctrl.Result{}, nil` and rely on
  the user editing the spec to trigger requeue.

**Effort:** 1-2h including a unit test for the requeue-on-RBAC path.

**Risk:** Low. Replaces exponential backoff with a tight loop;
ensure transient classification doesn't include programmer errors
(would mask bugs as "retry forever").

### F48. KVI operator — audit pods/proxy + pods verb coverage

**Why:** Two RBAC gaps escaped review (`pods update`, `pods/proxy update`)
because the controller-gen markers were copy-pasted from kubebuilder
defaults and never compared against what the controller actually
calls. Both surfaced live in C1 — fixed in the same session but
trivially preventable.

**What to do:** Walk every OpenBao API call the controller makes
(init, unseal, raft-join, mount-create, approle-create, mount-tune,
audit-enable, …) and confirm the corresponding HTTP verb on
`/api/v1/namespaces/{ns}/pods/{pod}:port/proxy/...` is covered in
the kubebuilder:rbac marker. Same audit for `pods` (label/annotation
patches, deletion for raft cleanup, etc.).

**Effort:** 2h. Mostly mechanical: open `crds/keyvault/internal/controller/openbao/*.go`,
match each HTTP method → required RBAC verb, update the marker comment,
`make manifests`, diff `config/rbac/role.yaml`.

**Risk:** Low. Strictly additive; the existing markers stay valid.

## How to use this file

- New entries go at the bottom of their section.
- An entry should explain *why*, *what*, *effort*, *risk*. The fresh
  agent shouldn't have to ask follow-up questions to start work.
- When you start an item, you don't need to mark it in this file —
  start the work, ship the PR, delete the entry in that PR.
