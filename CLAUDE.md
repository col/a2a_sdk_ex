# CLAUDE.md

Guidance for working in this repository.

## Project

`a2a_sdk_ex` is an Elixir SDK (hex package `:a2a`, module namespace `A2A`) for
building **A2A (Agent2Agent)** protocol-compliant agents. It is the Elixir
counterpart to the official [Python](https://github.com/a2aproject/a2a-python)
and [JS/TS](https://github.com/a2aproject/a2a-js) SDKs.

**Phase 1 (current):** the typed foundation — hand-written `A2A.Types.*` structs
for the core task/message flow, the `A2A.JSON` proto3-JSON codec, and a
test-only proto-conformance harness. It has no dependency on any other SDK
component, starts no processes, and opens no sockets. Runtime dependency graph
is **`jason` only**.

The full A2A v1.0 type surface (44 messages + 2 enums) is delivered across **4
phases**; Phase 1 covers 12 core messages + both enums. Phases 2–4 (agent card,
security schemes, push/listing) are tracked as explicit deferrals in the
coverage manifest.

## Common commands

| Command | Purpose |
| --- | --- |
| `mix deps.get` | Fetch dependencies |
| `mix precommit` | Run the full pre-push gate — format check, `compile --warnings-as-errors`, `credo --strict`, `test`, `dialyzer` (mirrors CI's toolchain-free `test` job). Run before pushing |
| `mix test` | Run the suite. **Green with no extra toolchain** — proto tests are excluded by default |
| `mix test.proto` (alias for `mix test --only proto`) | Run the proto-conformance harness (needs `protoc` + `protoc-gen-elixir`) |
| `mix a2a.gen_proto` | Regenerate the throwaway proto oracle modules into `test/support/gen/` (git-ignored). **Not part of `mix compile`** |
| `mix format --check-formatted` | Formatting gate (excludes the generated proto subtree) |
| `mix credo --strict` | Lint gate (kept clean) |
| `mix dialyzer` | Type checking (CI) |
| `mix docs` | Build ExDoc (HexDocs) |

The required Elixir version is declared in `mix.exs` (`elixir:`) — check it there
rather than assuming. `mix.lock` pins some dev/test deps deliberately; don't bump
them casually.

## Architecture

- **`A2A.Types.*`** — hand-written idiomatic structs (atoms for enums,
  snake_case fields, tagged unions). Each type module exports a **field spec**
  via `__a2a_fields__/0` (a list of `%A2A.Types.Field{}`) that maps struct field
  ⇄ proto field name/number/wire-type/cardinality/oneof. Union modules
  (`Part`, `StreamResponse`, `SendMessageResponse`) also export
  `__a2a_discriminator__/0` (`:kind`). The field spec is the single source of
  truth.
- **`A2A.JSON`** — one **generic** proto3-JSON codec (`encode/1`, `decode/2`,
  plus low-level `to_json_map/1` / `from_json_map/2`) driven entirely by the
  field specs. There is **no per-struct encode/decode logic** — add a type by
  writing its struct + field spec, not by touching the codec. `_UNSPECIFIED`
  (proto zero) enum values are rejected on decode and never emitted.
- **Proto-conformance harness** (`test/`, `@tag :proto`, never shipped) — proves
  the hand-written types are complete and compliant against the pinned official
  `.proto` without generating shipped types from it. `mix a2a.gen_proto` builds
  throwaway oracle modules used as a differential oracle (Tier 2) plus a
  descriptor-driven completeness partition (Tier 1). The coverage manifest
  (`test/support/coverage.ex`) asserts `covered ∪ deferred == all proto
  messages` (disjoint), so a new proto release that adds a message fails loudly.

## Conventions

- **Proto is the authority for shapes and field names.** The vendored, pinned
  `priv/proto/a2a.proto` (see `priv/proto/PROTO_VERSION`) is authoritative. Field
  specs must match it exactly (names, numbers, cardinality, oneofs). `Part` is
  modeled **proto-faithfully** — `kind: :text | :raw | :url | :data` (one field
  per `content` oneof arm), NOT the reference SDKs' `:file` grouping. Enum
  spelling follows the proto (US `:canceled` → `"TASK_STATE_CANCELED"`).
- **TDD.** Write the failing test first; the everyday `mix test` must stay green
  with no proto toolchain.
- Keep the runtime dependency graph minimal (`jason` only for now).

## Documentation policy

Under `docs/`:

- **Commit:** spec docs (`docs/superpowers/specs/`), architecture docs, and ADR
  records. These are the durable design record and travel with the code.
- **Do NOT commit:** Superpowers **plan** docs (`docs/superpowers/plans/`). They
  are transient working artifacts and are git-ignored. Write and use them
  locally, but keep them out of version control.
