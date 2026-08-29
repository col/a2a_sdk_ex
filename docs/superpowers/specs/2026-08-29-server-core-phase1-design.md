# Server core — Phase 1: the OTP walking skeleton

Status: approved (brainstorm 2026-08-29)
Branch: `throng/AA-10`

## Purpose

The typed foundation (`A2A.Types.*` + `A2A.JSON`) is complete. This spec opens
the **server runtime** — the OTP-native core the whole SDK is built to prove.
It delivers the thinnest **vertical slice** through every documented seam: a
real agent, driven end-to-end, returns a spec-compliant `Task`.

Following the project's unifying principle — *"prove the OTP-native core against
a real, streaming, cancellable, resumable, webhook-delivering agent before
broadening"* ([scope-and-roadmap](../../architecture/scope-and-roadmap.md)) —
Phase 1 proves the **wiring** (supervision tree, process-per-task, PubSub event
path, store projection, handler orchestration) against a **blocking**
`message/send`. Streaming, cancel, push, listing, and the HTTP transports are
deferred to named follow-on phases (see [Deferred](#deferred--follow-on-phases)).

The outer edge of this phase is the **`DefaultHandler` API**, driven by tests —
**no Plug/HTTP dependency this phase** (decided in brainstorm). The event path
built here (`TaskUpdater` → PubSub topic → draining subscriber) is the *same*
path streaming and push will later attach to; a blocking send simply uses one
synchronous draining subscriber.

## Scope

### In

- `A2A.Server.Supervisor` — the mountable OTP tree (configurable
  `Phoenix.PubSub`, `Registry`, `DynamicSupervisor`, ETS store owner). Nothing
  global; everything passed at init (invariant 7).
- `A2A.Server.AgentExecutor` — the author-facing behaviour (`execute/2`,
  `cancel/2`; `cancel/2` is declared but unused this phase).
- `A2A.Server.RequestContext` — the read-side struct + helpers (`user_input/1`).
- `A2A.Server.TaskUpdater` — the ergonomic event emitter bound to a task.
- `A2A.Server.Events` — PubSub topic convention + broadcast/subscribe helpers.
- `A2A.Server.Execution` — the per-task process (one per `task_id`), plus its
  `Registry` and `DynamicSupervisor`.
- `A2A.Server.TaskStore` — the persistence behaviour (Phase 1 implements
  `save/2`, `get/2`, and `delete/2`; only `list/2` is deferred, declared as an
  `@optional_callbacks` and landing with the listing phase).
- `A2A.Server.TaskStore.ETS` — the default adapter.
- `A2A.Server.TaskStore.ConformanceCase` — the shared behaviour-conformance test
  suite (per [persistence](../../architecture/persistence.md)) the ETS default
  runs and future adapters reuse.
- `A2A.Scope` — tenant/owner scope; a default single-tenant scope this phase.
- `A2A.Server.RequestHandler` — the transport-agnostic behaviour (full callback
  surface declared; only a subset implemented this phase).
- `A2A.Server.DefaultHandler` — implements **`send_message/2` (blocking)** and
  **`get_task/2`** only.
- `A2A.Server.ResultAssembler` — folds an event stream into a `Task`.
- `A2A.User` — a minimal identity struct + stub resolver.

New runtime dependency: `:phoenix_pubsub` (`jason` already present). This is the
first runtime dep added beyond `jason` and is required by
[ADR-0005](../../architecture/decisions/0005-pubsub-process-model.md).

### Deferred — follow-on phases

Recorded here so the roadmap stays legible (mirrors the 4-phase data-model
split). Each is additive behind a boundary this phase establishes:

1. **Streaming** — `send_message_stream/2`, `resubscribe/2`, SSE; `StreamResponse`
   frames over the same event path. **This phase also reshapes the drain.** The
   Phase-1 blocking handler consumes events with a raw `receive` loop
   (`DefaultHandler.drain/1`) — correct because `send_message/2` runs in the
   caller's process, which subscribed to the topic, so PubSub delivers `%Event{}`
   straight to its mailbox. That inline `receive` only serves blocking mode and
   assumes the caller's mailbox is "ours" (fine for a test process, awkward inside
   a web-server-owned request process). Replace it with a subscription-backed
   **`A2A.Server.EventStream`** (a `Stream.resource/3` that subscribes on start,
   yields each `%Event{}`, and unsubscribes on halt/timeout). Both modes then
   share one path: **blocking** = `Enum.reduce_while/3` folding the stream to the
   terminal frame; **streaming** = pipe the same stream through the SSE encoder.
   The idle-timeout and unsubscribe live inside the stream resource, in one tested
   place, rather than inline in the handler.
2. **Cancellation** — `cancel_task/2`, Registry lookup → cancel message →
   `AgentExecutor.cancel/2`, hard-timeout escalation.
3. **HTTP transports** — `A2A.Plug.Router` (JSON-RPC + REST), agent-card endpoint
   at `/.well-known/agent-card.json`, `A2A.Standalone` (Bandit).
4. **Push notifications** — `PushConfigStore` behaviour + ETS, `Push.Sender`
   webhook delivery as another topic subscriber.
5. **Task listing** — `list_tasks/2` + store query surface.
6. **Extensions & real auth** — `A2A-Extensions` negotiation, `user_resolver`
   hook wired to a real identity.
7. **Configurable drain timeout** — Phase 1 hardcodes `@drain_timeout 30_000` in
   `DefaultHandler` as an **idle** timeout (it re-arms on every event via the
   `receive/after` recursion, so it bounds silence between events, not total task
   duration). Make it configurable: a server-level default (on the `A2A.Server`
   handle / supervisor opts) plus a per-request override via
   `SendMessageConfiguration`, including `:infinity`. Note the timeout abandons the
   blocking *wait*, not the *task* — the execution process keeps running and
   persists its terminal state, so a timed-out caller can still `get_task/2` the
   result. The intended answer to genuinely long-running work is non-blocking /
   streaming delivery, not a larger blocking timeout. (Pairs with the drain
   reshape in item 1.)

## Architecture

New `A2A.Server.*` namespace. Module layout:

| Module | Kind | Responsibility |
| --- | --- | --- |
| `A2A.Server.Supervisor` | Supervisor | The mountable tree; started with an options struct. |
| `A2A.Server.AgentExecutor` | behaviour | `execute/2`, `cancel/2`. The author's surface. |
| `A2A.Server.RequestContext` | struct + helpers | Read-side context handed to the executor. |
| `A2A.Server.TaskUpdater` | struct + funs | Emits correctly-shaped events; broadcasts + persists. |
| `A2A.Server.Events` | module | `topic/1`, `subscribe/2`, `broadcast/3`; event envelope. |
| `A2A.Server.Execution` | GenServer | One process per `task_id`; runs the executor. |
| `A2A.Server.Execution.Supervisor` | DynamicSupervisor | Supervises execution processes (`:transient`). |
| `A2A.Server.Execution.Registry` | Registry | `task_id → pid`, unique keys. |
| `A2A.Server.TaskStore` | behaviour | `save/2`, `get/2`, `delete/2` (`list/2` deferred). |
| `A2A.Server.TaskStore.ETS` | GenServer + impl | Default adapter; owns an ETS table. |
| `A2A.Server.RequestHandler` | behaviour | Full RPC surface declared; subset optional-callback'd. |
| `A2A.Server.DefaultHandler` | module | `send_message/2` (blocking) + `get_task/2`. |
| `A2A.Server.ResultAssembler` | module | Folds events → `Task`. |
| `A2A.User` | struct | Minimal identity; stub resolver. |

### Supervision tree

```
A2A.Server.Supervisor            # started with %A2A.Server.Options{}
├── {Phoenix.PubSub, name: opts.pubsub}   # or reuse host PubSub (skip if provided)
├── {Registry, keys: :unique, name: <Execution.Registry>}
├── {DynamicSupervisor, name: <Execution.Supervisor>, strategy: :one_for_one}
└── {A2A.Server.TaskStore.ETS, name: <store>}   # or user-provided store child
```

A configuration struct (`A2A.Server.Options` or equivalent keyword) carries:
`executor` (module), `task_store` (module + name), `pubsub` (name, optionally
pre-started by the host), `id_generator` (UUID default), `user_resolver` (stub
default). No global names; a host app mounts this whole subtree.

### Event envelope

Executor-emitted events flow as an internal envelope on the task topic. The
envelope wraps the domain event (`TaskStatusUpdateEvent` /
`TaskArtifactUpdateEvent` / `Task` / `Message`) with enough metadata for a
subscriber to know when the stream is terminal. Shape (sketch):

```elixir
%A2A.Server.Events.Event{
  task_id: String.t(),
  context_id: String.t(),
  payload: TaskStatusUpdateEvent.t() | TaskArtifactUpdateEvent.t() | Task.t() | Message.t(),
  terminal?: boolean()   # true for completed/failed/canceled/rejected/input_required
}
```

Broadcast on topic `"a2a:task:<task_id>"` via `Phoenix.PubSub`.

## Data flow — blocking `send_message`

1. **Resolve identity & task.** `DefaultHandler.send_message/2` receives a
   `SendMessageRequest` (or the extracted `Message` + `SendMessageConfiguration`).
   It resolves `task_id` / `context_id` (from the incoming message, else
   generated by the id generator), loads any existing task via
   `TaskStore.get/2` (`{:error, :not_found}` for a fresh task), and **rejects
   continuation of a terminal task** with an
   `A2A.Error` (invariant 5).
2. **Build context & subscribe first.** Build the `RequestContext` (message,
   ids, existing task, stub `user`, config, metadata). **Subscribe to the task
   topic before starting the execution** so no early event is missed.
3. **Start the execution process.** Start `A2A.Server.Execution` under the
   `DynamicSupervisor`, registered by `task_id` in the `Registry` — enforcing
   one process per task (invariant 1). Starting an already-registered task is a
   continuation (re-uses the process where applicable); for Phase 1 a fresh task
   is the common path.
4. **Executor runs; events flow one way.** The process builds a `TaskUpdater`
   bound to the task and invokes `AgentExecutor.execute/2`. Each `TaskUpdater`
   call **broadcasts** the event envelope on the topic **and persists** the
   projected `Task` via `TaskStore.save/2`. The executor emits; it never returns
   output (contract mirrors reference SDKs). The **first** emitted event must be
   a `task`/`message` (start-of-work).
5. **Drain & assemble.** The handler, as the synchronous draining subscriber,
   feeds each envelope through `ResultAssembler` until a `terminal?` envelope
   (terminal state or `input_required`), then returns the assembled `%Task{}`
   (or a bare `%Message{}` when the agent replied with a message).
6. **Failure & exit.** An unhandled raise in the executor is caught → the task
   transitions to `failed` (terminal) and that envelope is what the drainer
   returns. On terminal state the execution process exits `:normal`.

### ResultAssembler folding rules

- Status update → replace `task.status`; append the status `message` to
  `task.history` when present.
- Artifact update → merge into `task.artifacts` by `artifact_id`
  (append/last-chunk aware via `append` / `last_chunk`).
- `Task` event → adopt as the current snapshot (start-of-work).
- Terminal states (`completed`/`failed`/`canceled`/`rejected`) **freeze** the
  task — no further mutation (invariant 5).

### `TaskUpdater` surface (Phase 1 subset)

Full surface is documented in
[request-handling](../../architecture/request-handling.md); Phase 1 implements
the blocking-path calls:

| Function | Emits |
| --- | --- |
| `start_work/1` | `working` status (start-of-work `task`) |
| `update_status/3` | arbitrary status + optional message |
| `add_artifact/3` | artifact-update event |
| `complete/2` | terminal `completed` |
| `fail/2` | terminal `failed` |
| `reject/2` | terminal `rejected` |
| `requires_input/2` | `input_required` (ends the blocking drain) |

`cancel/2` and `requires_auth/2` are declared/documented but exercised in the
cancellation and streaming phases respectively.

## Error handling

- `A2A.Error` — a minimal error struct/exception used for protocol-level
  rejections (terminal-task continuation, unknown task on `get_task`). JSON-RPC
  error-code mapping arrives with the transports phase; this phase returns
  tagged `{:error, %A2A.Error{}}` from handler functions.
- Executor raises are caught at the execution-process boundary → `failed`.
- A crash of the execution process (not a caught raise) is observed by the
  `DynamicSupervisor`; the drainer returns/records `failed`. One task crashing
  never affects another (per-process isolation).

## Testing strategy (TDD)

Everyday `mix test` **stays green with no new toolchain** (the proto group
remains opt-in). New tests live under `test/a2a/server/`.

- **Unit — `TaskUpdater`:** each call produces a correctly-shaped domain event;
  round-trip the emitted event through `A2A.JSON` to assert codec validity.
- **Unit — `ResultAssembler`:** artifact merge by `artifact_id`, history
  accumulation, status replacement, terminal freeze (further events ignored).
- **Unit — `TaskStore.ETS`:** `save`/`get` round-trip; missing task →
  `{:error, :not_found}`; runs the shared
  `A2A.Server.TaskStore.ConformanceCase` suite.
- **Process — `Execution`:** one-per-`task_id` registration (second start is
  rejected/deduped); executor raise → `failed` terminal + `:normal`-vs-crash
  exit semantics; terminal state → process exits `:normal`.
- **Integration — walking skeleton:** a demo `EchoExecutor` (in `test/support`)
  driven end-to-end through `DefaultHandler`. `send_message/2` (blocking)
  returns a `completed` `Task` whose artifact echoes the input; `get_task/2`
  reads the same task back from the store.
- **Property:** an executor that emits a random *valid* event sequence always
  assembles to a codec-valid `Task` (reuse the Phase-1 `StreamData` generators).

## Interop note

This phase adds no wire surface, so the interop-oracle work (driving the server
with reference-SDK clients) begins with the transports phase. Phase 1's codec
round-trip assertions keep every emitted event wire-faithful in the meantime.

## Documentation & housekeeping

- Update `A2A` moduledoc and `README.md` status line to note the server core has
  begun (the type-only framing is now outdated).
- No ADR change required — this phase *implements* ADR-0005/0006/0007/0008 as
  specified; if an implementation choice diverges from an ADR, add a new ADR
  rather than editing the record.
- `CLAUDE.md` architecture section updated once the phase lands.

## Related

- [Architecture overview](../../architecture.md)
- [Process model](../../architecture/process-model.md)
- [Request handling](../../architecture/request-handling.md)
- [Persistence](../../architecture/persistence.md)
- [Scope and roadmap](../../architecture/scope-and-roadmap.md)
- ADRs [0005](../../architecture/decisions/0005-pubsub-process-model.md),
  [0007](../../architecture/decisions/0007-ets-task-store.md),
  [0008](../../architecture/decisions/0008-v1-feature-tiers.md)
</content>
</invoke>
