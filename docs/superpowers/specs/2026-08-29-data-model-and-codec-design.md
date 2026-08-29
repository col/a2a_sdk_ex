# Data model & `A2A.JSON` codec — design spec

**Status:** approved (brainstorm), pending implementation plan
**Date:** 2026-08-29
**Feature:** Phase 1, first feature of the A2A Elixir SDK (`a2a`)
**Branch:** `feature/data-model-and-codec` (off `main`) — draft PR #2

> Architecture context lives in [`docs/architecture.md`](../../architecture.md) and
> its detail set (currently in PR #1, branch `sdk-architecture-planning`). This
> spec realizes the [Data model](../../architecture/data-model.md) component and
> the [interop-validation workstream](../../architecture/scope-and-roadmap.md#interop-validation-cross-cutting-workstream).

## 1. Goal & scope

Build the typed foundation of the SDK: hand-written idiomatic Elixir structs for
the A2A v1.0 type surface, plus the `A2A.JSON` proto3-JSON codec that owns all
wire fidelity — and a **proto-driven validation harness** that proves those
hand-written types are *complete* and *compliant* against the official A2A
`.proto`, without generating the shipped types from it.

The type surface is delivered across **four phases** (§2.1). **This spec is
Phase 1**, which additionally builds the codec and the *entire* validation
harness up front — the harness supports phasing via an explicit coverage manifest
(§5.3) so later phases only add structs, not machinery.

This is the foundation every later feature depends on. It has no dependency on
any other SDK component and is built and tested in isolation.

### In scope (Phase 1)

- The **core task/message flow** structs (§2.1, 12 messages + 2 enums).
- `A2A.JSON` — `encode/1` and `decode/2` implementing proto3-JSON (full rule set).
- The **complete** test-only proto-validation harness (completeness + compliance),
  including the coverage manifest that lets Phases 2–4 be tracked as explicit
  deferrals.
- Project scaffolding: `mix.exs`, deps, formatter, Credo, Dialyzer, CI, ExDoc.

### Out of scope

- **Phases 2–4 type structs** (agent card, security, push/listing — §2.1). They
  are explicitly listed in the harness `@deferred` manifest so completeness stays
  provable per phase.
- Server behaviours (`AgentExecutor`, `RequestHandler`), transports/Plug,
  execution processes, persistence stores, telemetry, push delivery. Nothing in
  this feature starts a process or opens a socket.

## 2. Design decision recap (from brainstorm)

| Decision | Choice |
| --- | --- |
| First feature | Data model + `A2A.JSON` codec |
| Proto validation | **Approach 2** — generate throwaway proto modules in the test env as a differential oracle, plus a small golden-file backstop |
| Proto toolchain | Dev/CI dependency (`protoc` + `protoc-gen-elixir`); generated code **never shipped** |
| Type coverage | Full v1.0 surface, delivered in **4 phases**; completeness test enforces the partition (§5.3) |
| Phasing | Harness built in full in Phase 1; later phases add structs + move them from `@deferred` to covered |

**Why validate against the proto rather than generate from it** — ADR-0004 keeps
the public API idiomatic (atoms, tagged structs, snake_case) instead of leaking
proto artifacts (integer enums, `_UNSPECIFIED`, oneof wrappers). But the proto
is still the *authority* for shapes and field names. This harness turns that
authority into an enforced, self-maintaining guarantee: bump the pinned proto and
completeness/compliance re-verify automatically — which is also how we absorb
future proto releases.

### 2.1 Phasing of the type surface (44 messages + 2 enums)

| Phase | Concern | Messages / enums |
| --- | --- | --- |
| **1 (this spec)** | Core task/message flow | `Message`, `Task`, `TaskStatus`, `Part`, `Artifact`, `TaskStatusUpdateEvent`, `TaskArtifactUpdateEvent`, `StreamResponse`, `SendMessageRequest`, `SendMessageResponse`, `SendMessageConfiguration`, `GetTaskRequest`; enums `TaskState`, `Role` |
| 2 | Agent card & discovery | `AgentCard`, `AgentInterface`, `AgentProvider`, `AgentCapabilities`, `AgentExtension`, `AgentSkill`, `AgentCardSignature`, `GetExtendedAgentCardRequest` |
| 3 | Security schemes | `SecurityScheme`, `APIKeySecurityScheme`, `HTTPAuthSecurityScheme`, `OAuth2SecurityScheme`, `OpenIdConnectSecurityScheme`, `MutualTlsSecurityScheme`, `SecurityRequirement`, `OAuthFlows`, `AuthorizationCodeOAuthFlow`, `ClientCredentialsOAuthFlow`, `ImplicitOAuthFlow`, `PasswordOAuthFlow`, `DeviceCodeOAuthFlow`, `AuthenticationInfo` |
| 4 | Push notifications & task listing | `TaskPushNotificationConfig`, `GetTaskPushNotificationConfigRequest`, `DeleteTaskPushNotificationConfigRequest`, `ListTaskPushNotificationConfigsRequest`, `ListTaskPushNotificationConfigsResponse`, `ListTasksRequest`, `ListTasksResponse`, `CancelTaskRequest`, `SubscribeToTaskRequest`, `StringList` |

Phases 2–4 are separate specs/plans that each move their messages from `@deferred`
to covered; they add no harness machinery.

## 3. The type surface (`A2A.Types.*`)

Structs are organized by concern (not one-file-per-message). Phase 1 delivers the
core-flow modules; later modules are noted for context.

- **`A2A.Types.Message`, `.Task`, `.TaskStatus`, `.Part`, `.Artifact`** — core
  conversation/task types. *(Phase 1)*
- **`A2A.Types.Events`** — `TaskStatusUpdateEvent`, `TaskArtifactUpdateEvent`,
  and the `StreamResponse` tagged union. *(Phase 1)*
- **`A2A.Types.Requests`** — RPC envelopes. Phase 1: `SendMessageRequest`,
  `SendMessageResponse`, `SendMessageConfiguration`, `GetTaskRequest`. Phase 4
  adds the remaining request/response messages + `StringList`.
- **`A2A.Types.Enums`** — `TaskState`, `Role` as atoms. *(Phase 1)*
- **`A2A.Types.AgentCard`** (+ card sub-structs) — *(Phase 2)*.
- **`A2A.Types.Security`** — scheme variants, flows, `AuthenticationInfo` —
  *(Phase 3)*.

### Idiomatic choices

- **Enums are atoms.** `TaskState`:
  `:submitted | :working | :completed | :failed | :canceled | :input_required |
  :auth_required | :rejected`. `Role`: `:user | :agent`.
- **`_UNSPECIFIED` zero values** are rejected on decode and never emitted on
  encode.
- **`Part` is a `kind`-tagged struct** (`:text | :file | :data`); likewise the
  `SendMessageResponse` (`task | message`) and `StreamResponse`
  (`task | message | status_update | artifact_update`) unions — so matching is
  exhaustive and explicit.
- **snake_case** field names throughout.

### Field-spec metadata

Each struct carries a small internal **field spec** (struct field name ⇄ proto
field name/number, wire type, cardinality, oneof grouping). The codec is driven
by this table rather than bespoke per-struct encode/decode functions, and the
completeness harness checks this same table against the proto descriptor. Exact
representation (module attribute vs. `__a2a_fields__/0` callback) is an
implementation-plan decision.

## 4. `A2A.JSON` codec

Single module, public surface `encode/1` and `decode/2` (decode takes the target
type/module). Transports and everything else call these and never touch JSON
shape directly. The **full rule set is built in Phase 1** (later phases add no
codec logic, only structs). Rules:

- **Field naming:** snake_case ⇄ camelCase.
- **Enums:** atom ⇄ proto3-JSON SCREAMING_SNAKE string
  (`:input_required ⇄ "TASK_STATE_INPUT_REQUIRED"`).
- **`google.protobuf.Struct` / `Value`:** ⇄ plain Elixir maps / scalars
  (metadata, `params`, `header`, `Part.data`).
- **`google.protobuf.Timestamp`:** ⇄ ISO-8601 string.
- **`bytes`** (`Part` file `raw`): ⇄ base64.
- **int64-as-string:** implemented for forward-compat, but **currently
  unexercised** — the v1 proto has no `int64` field. Noted so a reviewer isn't
  surprised by untested-by-real-fields code; covered by synthetic tests only.
- **Tagged unions** dispatch on `kind`.

JSON encoding/decoding of the outer document uses `jason`.

## 5. Proto-validation harness (test-only)

Everything here is under `test/`; **nothing ships** in the compiled library. Built
in full in Phase 1.

### 5.1 Vendoring & codegen

- Vendor `specification/a2a.proto` (pinned to a specific A2A git ref, recorded in
  a `PROTO_VERSION` file) plus the required googleapis annotation protos
  (`google/api/annotations.proto`, `client.proto`, `field_behavior.proto`) and
  the well-known types, under `priv/proto/`.
- A mix task `mix a2a.gen_proto` runs `protoc` + `protoc-gen-elixir` into
  `test/support/gen/` (git-ignored). This is a **manual/CI step, not part of
  `mix compile`** — contributors without `protoc` can build and use the library;
  they only cannot run the proto group.
- Proto-conformance tests are tagged `@tag :proto` and **excluded by default**.
  `mix test` is always green with no toolchain; `mix test --only proto` (CI)
  requires the toolchain.

### 5.2 Tier 1 — Completeness (descriptor introspection)

Load the generated modules' descriptors; for every proto message/field/enum that
is **covered** (§5.3) assert:

- a hand-written struct exists,
- every proto field maps to a struct field (correct camelCase↔snake_case name and
  cardinality),
- no struct invents a field absent from the proto,
- every enum value maps to an atom, and vice-versa.

### 5.3 Coverage manifest & the partition rule

The mechanism that makes phasing safe. A checked-in manifest
(`test/support/coverage.ex`) declares two sets:

- **`covered`** — messages/enums with hand-written structs (derived from the
  `A2A.Types.*` modules, not a hand-maintained list, so it can't drift from the
  code).
- **`@deferred`** — an explicit list of `{message, phase, reason}` for messages
  intentionally postponed (Phases 2–4 in §2.1).

The completeness test asserts the **partition**:

```
proto_messages == covered ∪ deferred        (and covered ∩ deferred == ∅)
```

- A postponed message → on `@deferred` → green.
- A message a **new proto release** introduces → in *neither* set → **red**, named
  exactly. Drift is still caught even mid-phasing.

Tier 2 (compliance) runs only over `covered`; Tier 1 completeness runs over *all*
proto messages via the partition. As each later phase lands, its messages move
from `@deferred` into `covered`; when `@deferred` is empty the full surface is
proven complete.

### 5.4 Tier 2 — Compliance (differential oracle + golden backstop)

For representative instances of each **covered** type:

- `A2A.JSON.encode(struct)` equals the generated proto module's proto3-JSON
  output, and round-trips both directions;
- **property tests** (`stream_data`) assert `decode(encode(x)) == x` and
  cross-check against the oracle;
- a **small set of golden `.json` files** captured once from the reference SDKs /
  spec examples is the canonical truth on top of the oracle (guards against
  elixir-protobuf's own JSON quirks).

## 6. Project scaffolding

- **Library project** (`mix new a2a`, no `--sup` — the data model needs no
  supervision tree). Hex package `:a2a`.
- **Runtime deps:** `jason` only (keep the runtime graph minimal).
- **Dev/test deps:** `stream_data` (`:test`), `protobuf` + `google_protos` and
  the `protoc-gen-elixir` escript (`:dev`/`:test`), `ex_doc`, `credo`,
  `dialyxir`.
- **Tooling:** `.formatter.exs`, `.credo.exs`, Dialyzer; `.github/workflows/ci.yml`
  running format-check, Credo, `mix test`, and a **separate `--only proto` job**
  that installs `protoc`.
- **ExDoc `extras`** wired to the existing `docs/` set for HexDocs.

## 7. Testing strategy

TDD throughout (write the failing test first).

- `test/a2a/types/*` — per-struct construction/validation unit tests (Phase 1 set).
- `test/a2a/json_test.exs` — codec unit tests, one per rule (enums, Struct/Value,
  Timestamp, bytes, unions, `_UNSPECIFIED` rejection, int64-as-string synthetic).
- `test/a2a/proto_conformance_test.exs` — Tier 1 (all messages, partition) + Tier 2
  (covered messages), tagged `:proto`.
- `test/support/` — `coverage.ex` manifest, `stream_data` generators, fixtures,
  golden `.json` files.

## 8. Risks & mitigations

- **elixir-protobuf JSON compliance gaps** → golden files from reference SDKs are
  the ultimate oracle; the generated oracle is a convenience layer, not the sole
  truth.
- **Toolchain friction (protoc + googleapis imports)** → opt-in `:proto` group so
  the everyday `mix test` and library build never require the toolchain.
- **int64-as-string untested by real fields** → explicitly flagged; synthetic
  tests only, revisited if a future proto adds int64 fields.
- **Silent completeness gaps while phasing** → the partition rule (§5.3) hard-fails
  on any message that is neither covered nor explicitly deferred.

## 9. Definition of done (Phase 1)

- The Phase 1 core-flow messages + both enums exist as `A2A.Types.*` with field
  specs; all other proto messages are listed in `@deferred` with a phase + reason.
- `A2A.JSON.encode/1` + `decode/2` implement every rule in §4 (full set).
- The full harness exists: `mix test` green with no toolchain; `mix test --only
  proto` green in CI with the partition (§5.3) holding and Tier 2 compliance
  passing over the covered set.
- Golden-file round-trips pass byte-for-byte (modulo key order) for covered types.
- CI (format, Credo, Dialyzer, both test jobs) green; ExDoc builds.
