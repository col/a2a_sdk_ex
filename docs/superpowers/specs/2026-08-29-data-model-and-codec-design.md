# Data model & `A2A.JSON` codec — design spec

**Status:** approved (brainstorm), pending implementation plan
**Date:** 2026-08-29
**Feature:** Phase 1, first feature of the A2A Elixir SDK (`a2a`)
**Branch:** `feature/data-model-and-codec` (off `main`)

> Architecture context lives in [`docs/architecture.md`](../../architecture.md) and
> its detail set (currently in PR #1, branch `sdk-architecture-planning`). This
> spec realizes the [Data model](../../architecture/data-model.md) component and
> the [interop-validation workstream](../../architecture/scope-and-roadmap.md#interop-validation-cross-cutting-workstream).

## 1. Goal & scope

Build the typed foundation of the SDK: hand-written idiomatic Elixir structs for
the **full A2A v1.0 type surface**, plus the `A2A.JSON` proto3-JSON codec that
owns all wire fidelity — and a **proto-driven validation harness** that proves
those hand-written types are *complete* and *compliant* against the official A2A
`.proto`, without generating the shipped types from it.

This is the foundation every later feature depends on. It has no dependency on
any other SDK component and is built and tested in isolation.

### In scope

- All 44 messages + 2 enums from A2A `a2a.proto` (package `lf.a2a.v1`,
  proto3) as `A2A.Types.*` structs / atoms.
- `A2A.JSON` — `encode/1` and `decode/2` implementing proto3-JSON.
- A test-only proto-validation harness (completeness + compliance).
- Project scaffolding: `mix.exs`, deps, formatter, Credo, Dialyzer, CI, ExDoc.

### Out of scope (later features, per the roadmap)

Server behaviours (`AgentExecutor`, `RequestHandler`), transports/Plug,
execution processes, persistence stores, telemetry, push notifications. Nothing
in this feature starts a process or opens a socket.

## 2. Design decision recap (from brainstorm)

| Decision | Choice |
| --- | --- |
| First feature | Data model + `A2A.JSON` codec |
| Proto validation | **Approach 2** — generate throwaway proto modules in the test env as a differential oracle, plus a small golden-file backstop |
| Proto toolchain | Dev/CI dependency (`protoc` + `protoc-gen-elixir`); generated code **never shipped** |
| Type coverage | **Full v1.0 surface**; completeness test enforces 100% coverage |

**Why validate against the proto rather than generate from it** — ADR-0004 keeps
the public API idiomatic (atoms, tagged structs, snake_case) instead of leaking
proto artifacts (integer enums, `_UNSPECIFIED`, oneof wrappers). But the proto
is still the *authority* for shapes and field names. This harness turns that
authority into an enforced, self-maintaining guarantee: bump the pinned proto and
completeness/compliance re-verify automatically — which is also how we absorb
future proto releases.

## 3. The type surface (`A2A.Types.*`)

44 messages + 2 enums, organized by concern (not one-file-per-message):

- **`A2A.Types.Message`, `.Task`, `.TaskStatus`, `.Part`, `.Artifact`** — core
  conversation/task types.
- **`A2A.Types.Events`** — `TaskStatusUpdateEvent`, `TaskArtifactUpdateEvent`,
  and the `StreamResponse` tagged union.
- **`A2A.Types.AgentCard`** (+ `AgentInterface`, `AgentProvider`,
  `AgentCapabilities`, `AgentExtension`, `AgentSkill`, `AgentCardSignature`).
- **`A2A.Types.Security`** — `SecurityScheme` (5 variants: APIKey, HTTPAuth,
  OAuth2, OpenIdConnect, MutualTls), `SecurityRequirement`, `OAuthFlows` + the 5
  flow structs (AuthorizationCode, ClientCredentials, Implicit, Password,
  DeviceCode), `AuthenticationInfo`.
- **`A2A.Types.Requests`** — RPC request/response envelopes: `SendMessageRequest`,
  `SendMessageResponse`, `GetTaskRequest`, `ListTasksRequest`,
  `ListTasksResponse`, `CancelTaskRequest`, `SubscribeToTaskRequest`,
  `GetTaskPushNotificationConfigRequest`,
  `DeleteTaskPushNotificationConfigRequest`,
  `ListTaskPushNotificationConfigsRequest`,
  `ListTaskPushNotificationConfigsResponse`, `TaskPushNotificationConfig`,
  `GetExtendedAgentCardRequest`, `SendMessageConfiguration`, `StringList`.
- **`A2A.Types.Enums`** — `TaskState`, `Role` as atoms.

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
shape directly. Rules:

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

Everything here is under `test/`; **nothing ships** in the compiled library.

### Vendoring & codegen

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

### Tier 1 — Completeness (descriptor introspection)

Load the generated modules' descriptors; for every proto message/field/enum
assert:

- a hand-written struct exists,
- every proto field maps to a struct field (correct camelCase↔snake_case name and
  cardinality),
- no struct invents a field absent from the proto,
- every enum value maps to an atom, and vice-versa.

Green ⇒ provably complete. A pinned-proto bump surfaces new/renamed/removed
fields as an exact diff.

### Tier 2 — Compliance (differential oracle + golden backstop)

For representative instances of each type:

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

- `test/a2a/types/*` — per-struct construction/validation unit tests.
- `test/a2a/json_test.exs` — codec unit tests, one per rule (enums, Struct/Value,
  Timestamp, bytes, unions, `_UNSPECIFIED` rejection, int64-as-string synthetic).
- `test/a2a/proto_conformance_test.exs` — Tier 1 + Tier 2, tagged `:proto`.
- `test/support/` — `stream_data` generators, fixtures, golden `.json` files.

## 8. Risks & mitigations

- **elixir-protobuf JSON compliance gaps** → golden files from reference SDKs are
  the ultimate oracle; the generated oracle is a convenience layer, not the sole
  truth.
- **Toolchain friction (protoc + googleapis imports)** → opt-in `:proto` group so
  the everyday `mix test` and library build never require the toolchain.
- **int64-as-string untested by real fields** → explicitly flagged; synthetic
  tests only, revisited if a future proto adds int64 fields.

## 9. Definition of done

- All 44 messages + 2 enums exist as `A2A.Types.*` with field specs.
- `A2A.JSON.encode/1` + `decode/2` implement every rule in §4.
- `mix test` green with no toolchain; `mix test --only proto` green in CI with
  Tier 1 completeness at 100% and Tier 2 compliance passing.
- Golden-file round-trips pass byte-for-byte (modulo key order).
- CI (format, Credo, Dialyzer, both test jobs) green; ExDoc builds.
