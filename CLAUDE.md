# CLAUDE.md

Guidance for working in this repository.

## Project

`a2a_sdk_ex` is an Elixir SDK (hex package `:a2a`, module namespace `A2A`) for
building **A2A (Agent2Agent)** protocol-compliant agents. It is the Elixir
counterpart to the official [Python](https://github.com/a2aproject/a2a-python)
and [JS/TS](https://github.com/a2aproject/a2a-js) SDKs.

**The typed foundation** — hand-written `A2A.Types.*` structs for the full A2A
v1.0 type surface, the `A2A.JSON` proto3-JSON codec, and a test-only
proto-conformance harness. It has no dependency on any other SDK component,
starts no processes, and opens no sockets. Runtime dependency graph is
**`jason` only**.

The full A2A v1.0 type surface (44 messages + 2 enums) has been delivered
across **4 phases** (Phase 1: 12 core messages + both enums; Phases 2–4: agent
card, security schemes, and push/listing). Every proto message now has a
hand-written `A2A.Types.*` struct; the coverage manifest's `@deferred` list
(`test/support/coverage.ex`) is empty and is retained only as the drift guard
against future proto releases. The typed foundation itself still covers only
data-model shapes and codec — no transport, process, or socket behaviour — but
see the server runtime paragraph below.

The **server runtime** (`A2A.Server.*`) is now underway. Phase 1 delivered the OTP
walking skeleton (mountable supervision tree, process-per-task execution, PubSub
event path, ETS `TaskStore`, and a blocking `DefaultHandler.send_message/get_task`).
Phase 2 adds streaming — `DefaultHandler.send_message_stream/2` and `resubscribe/2`,
both served by the shared `A2A.Server.EventStream` (subscribe-and-yield with
three-signal termination, see ADR-0009), plus a configurable, SDK-side
`:drain_timeout` for the blocking path.

The **HTTP transport** has landed for both bindings (ADR-0010, ADR-0011):
`A2A.Plug.Router` (mountable `Plug.Router`) + `A2A.Plug.JSONRPC` (envelope
decode/dispatch) + `A2A.Plug.REST` (REST transport mechanics — path/query/body
→ typed request via `A2A.JSON`, `application/a2a+json` responses) +
`A2A.Plug.SSE` (streaming responses, shared by both bindings via a
frame-formatter argument), plus an optional `A2A.Standalone` (Bandit-backed)
for running without a host web framework. All six operations are wired on
both bindings — `message/send`, `message/stream`, `tasks/get`,
`tasks/cancel`, `tasks/list`, `tasks/resubscribe` — rendered via
`A2A.Error.to_jsonrpc/1` (JSON-RPC) or `A2A.Error.to_rest/1` (REST,
`google.rpc.Status` body), two projections of one error-code table. `plug` is
now a **hard** runtime dep; `bandit` is optional (only needed for
`A2A.Standalone`). Cancellation needed `A2A.Server.Execution` restructured to
run the author's `execute/2` in an unlinked, monitored **child process**, so
the `Execution` GenServer's mailbox stays free to handle a cancel call while
`execute/2` is in flight (see ADR-0011). Push-notification-config REST routes
and `/{tenant}/…` scoping remain deferred.

`examples/echo_server/` is a minimal runnable agent demonstrating the HTTP
transport end-to-end. It has its **own `mix.exs`** (path-deps on this repo) and
runs standalone via `mix run --no-halt` from that directory — it is **not**
part of this repo's `mix test` or `mix precommit`.

A2A spec conformance is measured with the official
[TCK](https://github.com/a2aproject/a2a-tck) via `scripts/run_tck.sh` (a
non-blocking, report-only `compliance` CI job runs it against the echo server on
every build) — see `docs/tck-compliance.md`. We are **not** compliant yet; the
harness exists to track the gap, not gate on it.

### Known constraints / gotchas (server runtime)

- **`A2A.Server.TaskStore.ETS` is globally named** (`name: __MODULE__`), so **two
  `A2A.Server.Supervisor` trees cannot run at once** — the second collides with
  `{:already_started}`. This partially bends invariant 7 ("nothing global"); it's
  a Phase-1 limitation left in place. **In tests**, don't `start_supervised!` a
  second tree to vary behaviour — reuse the setup server and override the field
  (`server = %{server | executor: MyExecutor}`); `DefaultHandler` reads
  `server.executor` at execution-start. A proper fix (per-instance ETS table +
  GenServer name) is a candidate before multi-tenant or the transports phase spins
  up concurrent servers.
- **Streaming enumerables must be enumerated once, in the calling process.**
  `send_message_stream/2` and `resubscribe/2` subscribe eagerly (in the caller)
  then return a lazy stream whose `receive` runs at enumeration time — enumerate
  it elsewhere and PubSub events land in the wrong mailbox; never enumerate it and
  the subscription leaks until the process dies. (Documented on both functions.)
- **Deferred (known-minor):** blocking `resolve_blocking` returns error code
  `:timeout` for *any* terminal-less end, including an executor that exits
  (`:DOWN`) without emitting a terminal. Distinguishing idle-timeout from `:DOWN`
  needs `EventStream` to surface a halt reason (a small contract change) — the
  result is correct, only the code/message is imprecise on a pathological path.

## Common commands

| Command | Purpose |
| --- | --- |
| `mix deps.get` | Fetch dependencies |
| `mix precommit` | Run the full pre-push gate — `hex.audit`, format check, `compile --warnings-as-errors`, `credo --strict`, `test`, `dialyzer` (mirrors CI's toolchain-free `test` job). Run before pushing |
| `mix test` | Run the suite. **Green with no extra toolchain** — proto tests are excluded by default |
| `mix test.proto` (alias for `mix test --only proto`) | Run the proto-conformance harness (needs `protoc` + `protoc-gen-elixir`) |
| `mix a2a.gen_proto` | Regenerate the throwaway proto oracle modules into `test/support/gen/` (git-ignored). **Not part of `mix compile`** |
| `mix format --check-formatted` | Formatting gate (excludes the generated proto subtree) |
| `mix credo --strict` | Lint gate (kept clean) |
| `mix dialyzer` | Type checking (CI) |
| `mix docs` | Build ExDoc (HexDocs) |
| `scripts/run_tck.sh` | Run the A2A TCK compliance suite against the echo server (needs a `../a2a-tck` checkout + `uv`; see `docs/tck-compliance.md`). Report-only, **not** part of `mix test` |

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
- Runtime dependency graph: `jason`, `phoenix_pubsub`, `plug` (+ optional
  `bandit` for `A2A.Standalone`). The typed foundation alone (`A2A.Types.*` +
  `A2A.JSON`) still depends on `jason` only.

## Documentation policy

Under `docs/`:

- **Commit:** spec docs (`docs/superpowers/specs/`), architecture docs, and ADR
  records. These are the durable design record and travel with the code.
- **Do NOT commit:** Superpowers **plan** docs (`docs/superpowers/plans/`). They
  are transient working artifacts and are git-ignored. Write and use them
  locally, but keep them out of version control.
