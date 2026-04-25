# Plan: GrooveGo as a Groove-like Kernel for an Anytype-style Object Graph

**Revised direction (supersedes earlier any-sync-shim plan).**

We will **not** try to embed Anytype on top of GrooveGo. Anytype's client is not designed to be a thin/pluggable frontend and fighting it is a dead end. Instead:

```
GrooveGo kernel        ← identity + membership + replication + trust
       ↓
Object Graph Layer     ← Anytype-inspired: objects, types, relations
       ↓
UI (web / desktop)     ← our own, thin, built on the layer above
```

The `AnyType-VPS/` folder stays in the repo as a **reference implementation** of the UX we're targeting and as the deployment playbook we'll gradually replace. It is not the product.

---

## 1. Why the earlier plan was wrong

The previous version proposed shimming the `any-sync` wire protocol and keeping the Anytype client untouched. Three problems:

1. **Anytype is tightly coupled to any-sync internals.** It is not a thin client. Wire-protocol drift between client versions would break us on every Anytype release.
2. **GrooveGo's substrate isn't ready to be anyone's backbone yet.** Today it only has a libp2p device identity (peer.ID = pubkey hash), a string-keyed workspace list with no signed membership, no CRDT module in `internal/sync/`, no per-object scoping. Putting a shim on top of that hides the real gap instead of closing it.
3. **The ceiling is low.** Even if the shim worked, the result is "self-hosted Anytype." The higher-value target is *"a semantically rich shared knowledge graph with real trust guarantees"* — which requires us to own the kernel and the graph layer.

---

## 2. Decisions locked in Phase 0 (the sharp definitions)

These are decided **before** any kernel code is written. They are the points the plan previously left under-specified, and getting any of them wrong later is expensive.

### 2.0.1 — Identity unit of truth
**Device-first internally, user-first externally.**
- Every signed op on the wire carries a **device** signature (low-ceremony, fast, no hardware/passphrase each write).
- A **user identity** is a root signing key that signs **device authorization certs**. Cert = `{userID, deviceID, capabilities, notBefore, notAfter}`, signed by the user's current root key.
- When verifying an op, peers check `device-sig(op)` AND `cert(device) ← user-sig`. The membership log stores *users*, not devices; devices are emergent delegates underneath.
- Consequence: rotating a device key doesn't touch membership; rotating a user key rewrites device certs and gossips a rotation record. Revoking a device revokes one cert. Revoking a user is a membership op.

### 2.0.2 — Membership model
**Event log primary, state snapshot is a derived cache.** History is never the optional thing.
- Ops: `Invite`, `Accept`, `Remove`, `ChangeRole`, `RotateWorkspaceKey`. Every op is signed and causally ordered by vector clock.
- Authority rules (concrete, not "role-based" hand-waving):
  - `admin` can issue `Invite`, `Remove`, `ChangeRole`, `RotateWorkspaceKey`.
  - `member` can issue `Accept` (of an invite addressed to them) and ops against objects they authored.
  - Founder of a workspace is the initial `admin`; admin count can never drop to zero (last admin cannot self-remove without promoting).
- An op is **valid** iff the signer had the required role at the op's causal frontier. This is replayable: given the log prefix, validity is a pure function.
- State snapshot (`{userID → role}`) is computed by replaying the log; it is cache-only and can be thrown away.

### 2.0.3 — Replication boundary / object scoping
**Objects are workspace-scoped. Object IDs are globally unique but logically owned by exactly one workspace.**
- `ObjectID = UUIDv7` — globally unique so that future cross-workspace references don't collide, but each object has a single *owner workspace* that holds its op log.
- An object cannot be edited from two workspaces. References from another workspace are **read-only links** (pinned to `{objectID, minVersion}`), not co-ownership.
- Cross-workspace / "global" objects are explicitly **out of scope until after Phase 6.** Their complexity (dedupe, multi-log conflict, shared membership) is deferred; the plan works without them.

### 2.0.4 — Encryption model (promoted to first-class)
Aligns encryption with membership — which was Groove's real strength, not the CRDT itself.
- **Workspace-log encryption:** every op is sealed with a symmetric **workspace key** before it hits GossipSub. Non-members see ciphertext only.
- **Workspace key rotation** is mandatory on `Remove` and on any key-compromise event. Rotation op emits a new key wrapped to each remaining member's user key (X25519 sealed box). Ops authored before rotation remain readable (old key is retained for replay); ops after rotation are only readable by the new-key set.
- **Per-object wrapping (optional):** sensitive objects carry a per-object symkey, itself wrapped to the workspace key. Allows "sensitive subsets" without a second workspace.
- **At-rest:** Badger store is encrypted with a device-local key derived from OS keychain / passphrase. Workspace keys are never written in plaintext.
- Key material is owned by `internal/identity/` and `internal/membership/`; no other module holds a plaintext key.

### 2.0.5 — Determinism invariant (single load-bearing rule)
> **Every op must be replayable from an empty node and produce identical state.**

This is the one sentence the whole kernel is designed around. It forces:
- no wall-clock timestamps in merge logic (use vector clocks + content hashes for tie-breaks),
- no hidden state outside the op log,
- no op whose effect depends on the *order of receipt* (only on causal order),
- deterministic iteration over sets (sorted by stable IDs before emitting derived ops).

Every PR against the kernel is checked against this invariant. A failing replay test is a blocker.

---

## 3. The four things the kernel must have

Non-negotiable for anything else to be safe to build on. These restate the requirements §2 decisions are answering.

### 2.1 Identity is not optional
Current state: libp2p **device** identity only (Ed25519 per host, peer.ID = pubkey hash).
Must add:
- **User identity** distinct from device identity (a user = a root signing key + a display name + metadata object).
- **Device identity** bound to a user via a signed device-authorization certificate.
- **Signing-key rotation** — new key signs a rotation record that chains to the previous key.
- **Revocation** — signed revocation records gossiped on workspace topics; receivers update their trust view.

### 2.2 Membership must be first-class
Current state: `workspace.Manager` stores `{name → Workspace}` with no signed ACL, no join/leave history.
Must add:
- **Workspace membership list** as a signed CRDT state (set of {userID, role, addedBy, addedAt}).
- **Signed membership changes** — every add/remove/role-change is a signed op by an authorized member, verifiable by everyone.
- **History of joins/leaves** — append-only, auditable. A removed member's past ops remain valid up to their removal timestamp.

### 2.3 Data must be scoped to shared contexts
Current state: no CRDT, `internal/sync/` is empty; replication model not yet chosen.
Must add:
- **Per-workspace logs** (one op log per workspace, not a global log). One GossipSub topic per workspace.
- **Per-object scoping** — every op names the object it touches; replication filters can subscribe to object subsets.
- **Clear replication boundaries** — which peers hold which logs is explicit and driven by membership, not best-effort gossip.
- **Per-object encryption (optional)** — workspace symmetric key for the common case; per-object keys for sensitive subsets.

### 2.4 Deterministic merge semantics
Must add:
- **Stable IDs** — UUIDv7 (or ULID) for objects; IDs never reused, never reassigned.
- **Versioning** — each object carries a vector-clock version; references pin to `{objectID, minVersion}` so links don't half-break offline.
- **Predictable conflict rules** — documented per-CRDT-type merge semantics (LWW-register, OR-set, RGA for text, etc.). No ad-hoc resolution.
- **Schema discipline** — object-type schemas are themselves versioned CRDT objects; schema changes are backward-compatible or bumped explicitly.

---

## 4. Architecture

```
┌──────────────── UI layer (later — our own, thin) ─────────────────┐
│  Web (progressive) and desktop shell. No Anytype client.          │
└──────────────────────────────┬────────────────────────────────────┘
                               ▼
┌──────────────── Object Graph Layer (Anytype-inspired) ────────────┐
│  objects · types · relations · blocks · views                     │
│  thin — translates UI intents to kernel ops                       │
└──────────────────────────────┬────────────────────────────────────┘
                               ▼
┌──────────────── GrooveGo kernel ──────────────────────────────────┐
│  identity/    user + device keys, rotation, revocation            │
│  membership/  signed ACL CRDT, join/leave history                 │
│  workspace/   per-workspace log, symmetric key, lifecycle         │
│  objects/     per-object op log, stable IDs, versioning           │
│  sync/        CRDT engine (Automerge or hand-rolled), merge rules │
│  store/       Badger — ops, blobs, vector clocks                  │
│  transport/   libp2p host + GossipSub per workspace               │
│  trust/       peer / org / federation graph (later phases)        │
└───────────────────────────────────────────────────────────────────┘
```

---

## 5. Phased build plan

Each phase leaves the system runnable and testable. Phases 1–4 are the kernel the user's feedback calls out as mandatory; 5–7 sit on top.

### Phase 0 — Survey & contract (2–3 days, no code)
- Audit current `internal/node|workspace|store|sync|transport|presence`. Produce `KERNEL-GAP.md`: for each of the four requirements in §3, list what exists, what's missing, what's wrong.
- Pick CRDT foundation: Automerge-go vs. hand-rolled per-object CRDTs. Recommendation: hand-rolled for the membership log (small, deterministic, auditable) + Automerge for rich object content (text, block trees).
- Write `KERNEL-SPEC.md` with the **§2 decisions** frozen and the concrete record formats:
  - Identity: `User`, `Device`, `DeviceCert`, `KeyRotation`, `Revocation` (fields, signatures, byte layout).
  - Membership: op wire format for `Invite` / `Accept` / `Remove` / `ChangeRole` / `RotateWorkspaceKey`; authority-check pseudocode.
  - Objects: op envelope `{wsID, objectID, version, schemaVersion, opBody, deviceSig, userCertRef}`; ciphertext framing.
  - Encryption: workspace key wrap format (sealed-box layout), per-object wrap format, rotation op payload.
- **Pressure-test the spec with scenarios before freezing it.** Walk through each on paper and confirm determinism and correctness:
  1. Device-less user joins from a new laptop (user key exists, no device cert yet).
  2. Admin Alice invites Bob while offline; Bob accepts; Alice and Carol reconcile on reconnect.
  3. Two admins concurrently remove the same member; vector clocks converge to a single `Remove`.
  4. Admin removes Bob; Bob (offline) authored an op just before removal; replayed op must be accepted, Bob's ops after removal must be rejected by all peers.
  5. User rotates root key; old device certs must remain verifiable for past ops but not accept new ones.
  6. Workspace key rotation on `Remove` — removed member's retained copy of old ciphertext still decrypts; new ops don't.
  7. Replay test: wipe a peer, re-sync from others, derived state (membership snapshot, object tree) byte-identical to the original.
- Only freeze `KERNEL-SPEC.md` after all seven scenarios pass on paper.

### Phase 1 — Identity kernel (≈1 week)
Delivers requirement 3.1, implementing decision §2.0.1.
- `internal/identity/`: `User`, `Device`, `DeviceCert`, `KeyRotation`, `Revocation`.
- Local keystore in Badger, encrypted at rest with a device-local key (OS keychain / passphrase) per §2.0.4.
- CLI: `groove id init`, `groove id add-device`, `groove id rotate`, `groove id revoke <device>`.
- libp2p peer.ID remains the transport identifier; every kernel op carries `device-sig(op)` + a reference to the signer's current `DeviceCert`. Verifiers check both.
- Tests (all must pass the replay invariant §2.0.5): rotation survives a round trip; revoked device's future ops are rejected; past ops remain valid; two peers replaying the same identity log arrive at byte-identical state.

### Phase 2 — Membership kernel (≈1 week)
Delivers requirement 3.2, implementing decision §2.0.2.
- `internal/membership/`: signed **event log** is primary storage; state snapshot `{userID → role}` is a rebuildable cache.
- Ops: `Invite`, `Accept`, `Remove`, `ChangeRole`, `RotateWorkspaceKey`. Every op signed and vector-clock ordered. Validity is a pure function of `(log prefix, op)` — no wall-clock reads.
- Authority rules per §2.0.2; last-admin self-removal is blocked; two concurrent `Remove`s of the same user converge to one.
- Rewrite `internal/workspace/manager.go`: workspaces keyed by **content-addressed workspace ID** (hash of genesis op), not a string. Carry `membership.Log` + current `workspaceKey`.
- Join flow: invite = signed capability token; joiner presents it; host verifies, appends `Accept`, hands back the current workspace key wrapped to the joiner's user key.
- Tests: membership history replays deterministically across peers (byte-identical state from empty); forged op is rejected by all peers; scenarios 2–4 from Phase 0 pass end-to-end.

### Phase 3 — Scoped replication & encryption (≈1 week)
Delivers requirements 3.3 and the encryption model §2.0.4. Implements decision §2.0.3.
- Per-workspace GossipSub topic `/groove/ws/<wsID>/ops/1.0.0`. No global op log.
- Per-object op log inside a workspace — ops tagged `{wsID, objectID, version}`. `objectID` is UUIDv7, globally unique, owned by exactly one workspace (§2.0.3). Cross-workspace references are read-only links and deferred.
- Every op **sealed with the workspace key before gossiping** — no plaintext ever leaves the process.
- `RotateWorkspaceKey` (introduced in Phase 2) is wired here: rotation emits a new key wrapped per-member (X25519 sealed box). Old key retained for replay of pre-rotation ops; new ops encrypted with new key only.
- Per-object wrapping supported for sensitive subsets (per-object symkey wrapped to workspace key).
- Tests: non-member receives ciphertext only; removed member cannot decrypt post-removal ops; pre-removal ops remain readable by replay; key rotation is deterministic (same log → same current key on every peer).

### Phase 4 — Deterministic merge (≈1 week)
Delivers requirement 3.4 and enforces §2.0.5.
- `internal/objects/`: `ObjectID` (UUIDv7), `Version` (vector clock), `Ref` (`{objectID, minVersion}`), `Op` (envelope from Phase 0).
- `internal/sync/`: Automerge for object content; hand-rolled CRDT for object metadata (type, relations). Merge rules per field kind documented in `KERNEL-SPEC.md`. No wall-clock inputs anywhere in merge.
- Schema registry: object-type schemas are themselves workspace objects. Ops reference `schemaVersion`; validation is a pure function of `(schema, op)`.
- **Replay test suite** is the gate for this phase: for every kernel op kind, wipe a peer, re-sync from the log, assert byte-identical derived state (membership snapshot, object tree, schema registry, workspace key). A failing replay is a blocker per §2.0.5.
- Tests: disjoint offline edits → commutative & idempotent merge; reference survives rename offline; schema bump with new required field doesn't invalidate old objects; scenario 7 from Phase 0 passes end-to-end.

**→ Checkpoint.** After Phase 4, GrooveGo is a real Groove-like kernel. Everything above this line was the user's feedback's "must have." Nothing below is safe to build without it.

### Phase 5 — Object graph layer (≈2 weeks)
- `pkg/graph/`: `Object`, `Type`, `Relation`, `Block`, `View` — thin Go types backed by kernel CRDTs. No UI here.
- JSON-RPC (or gRPC) local daemon API so any frontend can drive it: `ObjectCreate`, `ObjectUpdate`, `ObjectQuery`, `RelationSet`, `TypeDefine`, `ViewRender`.
- Reference tools ship as object types: `Note`, `Task`, `Channel` (chat), `Poll`, `Whiteboard`.

### Phase 6 — UI (≈3–4 weeks)
- Web UI first (progressive, works in any browser, thin). Desktop wraps it via Wails / Tauri-equivalent later.
- UI speaks only the Phase-5 daemon API. No Anytype client.
- Presence, chat, and calls reuse existing `internal/presence/` and GossipSub side-topics.

### Phase 7 — Interop with Anytype (optional, only if wanted)
- **Import** from an Anytype self-host: read MongoDB object trees, replay as kernel ops into a workspace. This is the useful direction.
- **Export** to Anytype: one-way dump in Anytype's space format for users who want out.
- No live shim, no wire-protocol emulation. If a user wants Anytype, they run Anytype.

### Phase 8 — Trust graph & federation (was capability 1 in the old plan)
Now a natural extension of Phase 1 once identity is real:
- `internal/trust/`: signed peer endorsements, orgs (named peer sets with rotating signing keys), federation links.
- Surfaced as first-class object types in the graph layer.

---

## 6. What lives where

```
GrooveGO/groove-go/
├── internal/
│   ├── identity/     # NEW  Phase 1
│   ├── membership/   # NEW  Phase 2
│   ├── workspace/    # REWRITE  Phase 2 (content-addressed IDs, ACL-backed)
│   ├── objects/      # NEW  Phase 4
│   ├── sync/         # FILL IN  Phase 4 (currently empty)
│   ├── store/        # extend for identity + membership + objects
│   ├── transport/    # per-workspace topics  Phase 3
│   ├── trust/        # NEW  Phase 8
│   ├── node | presence | apps | web   # existing
├── pkg/
│   ├── protocol/     # wire types  Phase 0 spec
│   └── graph/        # NEW  Phase 5 object-graph API
└── cmd/groove/       # CLI — new subcommands per phase

AnyType-VPS/          # reference implementation + deployment playbook
├── GROOVE-BACKEND-PLAN.md   # this file
├── anytype-*.md             # kept as reference, not the product
```

---

## 7. Honest assessment

- **Can GrooveGo be used?** Yes, as a foundation. Not today as a drop-in backbone.
- **Concrete next step:** Phase 0 — `KERNEL-GAP.md`, then `KERNEL-SPEC.md` with the §2 decisions frozen, then the seven scenario walk-throughs. No code until all seven pass on paper.
- **The payoff:** if Phases 0–4 land, the result is a *deterministic, identity-aware, membership-scoped replicated log system*. At that point the object-graph layer is almost easy, the UI is a projection (not a dependency), and chat / workflows / knowledge graph all ride the same substrate.

---

## 8. First concrete step

**Do Phase 0 now.** Deliverables, in order:
1. `GrooveGO/groove-go/KERNEL-GAP.md` — current state vs. the four requirements in §3.
2. `GrooveGO/groove-go/KERNEL-SPEC.md` — §2 decisions frozen, record formats defined, authority rules in pseudocode, encryption framing, determinism invariant at the top.
3. Seven scenario walk-throughs against the draft spec. Any scenario that doesn't resolve cleanly sends us back to #2. Only then does Phase 1 start.
