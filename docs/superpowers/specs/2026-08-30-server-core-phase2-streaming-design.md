# Server core — Phase 2: streaming

Status: approved (brainstorm 2026-08-30)
Branch: `throng/AA-11`

## Purpose

Server-core Phase 1 delivered the OTP walking skeleton: a mountable supervision
tree, process-per-task execution, the PubSub event path, an ETS `TaskStore`, and
a **blocking** `DefaultHandler.send_message/2` + `get_task/2`. This phase opens
the **streaming** delivery mode over the *same* event path, and — as Phase 1's
deferred list called for — reshapes the blocking drain into a shared,
subscription-backed stream that both modes consume.

Concretely, this phase implements deferred items **1 (Streaming)** and
**7 (Configurable drain timeout)** from the
[Phase 1 spec](2026-08-29-server-core-phase1-design.md#deferred--follow-on-phases):

- `send_message_stream/2` and `resubscribe/2`, each returning a lazy
  `Enumerable.t()` of `%A2A.Types.StreamResponse{}` frames over the existing
  PubSub topic.
- A shared **`A2A.Server.EventStream`** (`Stream.resource/3`) that replaces the
  raw `receive` loop in `DefaultHandler.drain/1`. Blocking =
  `Enum.reduce_while/3` folding the stream to the terminal frame; streaming =
  `Stream.map/2` projecting each event to a `StreamResponse` frame.
- A configurable **idle** drain timeout (server default + per-request SDK-side
  override, including `:infinity`), now backstopped by execution-process
  monitoring inside `EventStream`.

The outer edge remains the **`DefaultHandler` / `RequestHandler` API**, driven by
tests — **no Plug/HTTP dependency this phase** (confirmed in brainstorm; the SSE
wire encoder and `A2A.Plug.Router` stay in the transports phase, which will
simply consume the `StreamResponse` enumerable this phase produces). No new
runtime dependencies: still `jason` + `phoenix_pubsub`.

## Scope

### In

- `A2A.Server.EventStream` — a `Stream.resource/3` that subscribes to a task
  topic on start, yields each `%A2A.Server.Events.Event{}` envelope, monitors the
  execution process, and halts on a terminal event, an execution `:DOWN`, or an
  idle timeout; unsubscribes and demonitors on halt.
- `A2A.Server.DefaultHandler`:
  - `send_message_stream/2` — returns `EventStream |> Stream.map(&to StreamResponse/1)`.
  - `resubscribe/2` — subscribe-first, then a store snapshot catch-up frame
    concatenated with the live stream.
  - `send_message/2` reworked onto `EventStream` (via `Enum.reduce_while/3`);
    the raw `receive` in `drain/1` is deleted.
  - `drain_timeout` threaded from the server handle + a per-request SDK-side
    override.
- `A2A.Server` handle gains a `drain_timeout` field (default `:infinity`),
  plumbed through `A2A.Server.Supervisor` options.
- A `StreamResponse` projection helper (event envelope → `%StreamResponse{}`).
- New ADR: EventStream termination model (terminal event | execution `:DOWN` |
  idle timeout).

### Out (unchanged deferrals)

- **HTTP transports** — `A2A.Plug.Router`, `A2A.Plug.SSE` wire encoder, the
  agent-card endpoint, `A2A.Standalone` (Bandit). This phase produces the
  frame enumerable those will encode; it adds no wire surface.
- **Cancellation**, **push notifications**, **task listing**,
  **extensions & real auth** — as per the Phase 1 deferred list.
- **Non-blocking `return_immediately`** send mode — a distinct behaviour;
  explicitly deferred (the proto field is left unimplemented this phase).
- **Event-log task store** — resubscribe uses the folded snapshot (see
  [Resubscription](#resubscription)); a frame-faithful event-log adapter is a
  possible *future* store variant, recorded as deferred, not built now.

## Architecture

### `A2A.Server.EventStream`

A `Stream.resource/3` — one tested place owning subscription lifecycle and
termination — driving both delivery modes. It yields the **domain-level**
`%A2A.Server.Events.Event{}` envelope (not the wire `StreamResponse`), so the
blocking assembler and the later push sender can reuse it unchanged.

```elixir
# sketch
def stream(pubsub, task_id, opts \\ []) do
  idle_timeout = Keyword.get(opts, :idle_timeout, :infinity)
  exec_pid     = Keyword.get(opts, :monitor)   # registered execution pid, or nil

  Stream.resource(
    fn -> start(pubsub, task_id, exec_pid) end,   # subscribe + monitor
    fn acc -> next(acc, idle_timeout) end,        # receive one event / :DOWN / timeout
    fn acc -> stop(pubsub, task_id, acc) end       # unsubscribe + demonitor
  )
end
```

- **start** — `Events.subscribe(pubsub, task_id)`; if an `exec_pid` is given,
  `Process.monitor(exec_pid)` and keep the ref.
- **next** —
  - `%Event{terminal?: true} = e` → `{[e], {:halt_after, acc}}` on the *next*
    pull (emit the terminal event, then halt). Implemented by emitting `[e]`
    with an acc flag so the terminal frame is delivered before the stream ends.
  - `%Event{} = e` → `{[e], acc}`.
  - `{:DOWN, ref, :process, _pid, _reason}` (our ref) → `{:halt, acc}` — the
    execution process is gone; no further events will come.
  - `after idle_timeout` → `{:halt, {:timeout, acc}}` (never fires when
    `:infinity`).
- **stop** — `Events.unsubscribe(pubsub, task_id)`; `Process.demonitor(ref, [:flush])`.

The subtlety: the terminal `%Event{}` must be *yielded* and then halt. The
resource acc carries a small tag so the pull that returns the terminal event is
followed by a pull that returns `{:halt, acc}`.

**Termination is the union of three signals**, recorded in the ADR:

1. a `terminal?` event (terminal state or `input_required`),
2. execution-process `:DOWN` (deterministic crash/exit detection — replaces the
   blind idle timer as the primary safety net),
3. an idle timeout (defense-in-depth for a *silent hang*: a live process that
   emits nothing and never exits; `:infinity` disables it).

`auth_required` is **not** terminal (invariant 6) — the stream stays open.

### Consumers

**Blocking** (`send_message/2`):

```elixir
EventStream.stream(pubsub, task_id, monitor: exec_pid, idle_timeout: timeout)
|> Enum.reduce_while(ResultAssembler.init(task_id, context_id), fn %Event{} = e, acc ->
     acc = ResultAssembler.apply(acc, e.payload)
     if e.terminal?, do: {:halt, acc}, else: {:cont, acc}
   end)
```

Returns the assembled `%Task{}` (or a bare `%Message{}` when the agent replied
with a message). If the stream ends **without** a terminal event (execution
`:DOWN` before terminal, or idle timeout), the handler resolves the result:

- read the store projection for `task_id`; if a `%Task{}` exists (the execution
  boundary persists `failed` on a caught raise), return it;
- otherwise return `{:error, %A2A.Error{code: :internal_error | :timeout, ...}}`.

**Streaming** (`send_message_stream/2`):

```elixir
EventStream.stream(pubsub, task_id, monitor: exec_pid, idle_timeout: :infinity)
|> Stream.map(&to_stream_response(&1.payload))
```

Returns a lazy `Enumerable.t()` of `%StreamResponse{}`. Termination follows the
same three signals; `auth_required` does not stop it.

### `StreamResponse` projection

A pure helper mapping an event payload to a wire frame, reusing the existing
`A2A.Types.StreamResponse` constructors:

| Payload | Frame |
| --- | --- |
| `%Task{}` | `StreamResponse.task/1` |
| `%Message{}` | `StreamResponse.message/1` |
| `%TaskStatusUpdateEvent{}` | `StreamResponse.status_update/1` |
| `%TaskArtifactUpdateEvent{}` | `StreamResponse.artifact_update/1` |

### Resubscription

`resubscribe/2` attaches a **new** subscriber to an already-live (or completed)
task. Per [streaming-and-events](../../architecture/streaming-and-events.md),
events emitted *before* the attach are caught up from the `TaskStore`
projection; events after arrive live.

The store holds a single **folded `%Task{}` snapshot**, not an event log — so the
faithful catch-up is exactly **one** `StreamResponse{kind: :task}` frame carrying
the current snapshot, then live frames. This matches the reference SDKs' behavior
and the A2A wire protocol, which has no resubscribe cursor (`tasks/resubscribe`
carries only a task id, so "resume from a point" is not expressible; "attach and
get current state" is the defined semantics).

Ordering, to avoid a catch-up/live gap (**subscribe first, then read snapshot**):

```elixir
:ok = Events.subscribe(pubsub, task_id)          # 1. live subscription first
case store.get(task_id, scope) do
  {:error, :not_found} ->
    :ok = Events.unsubscribe(pubsub, task_id)
    {:error, A2A.Error.not_found(task_id)}
  {:ok, task} ->
    snapshot = StreamResponse.task(task)          # 2. snapshot after subscribing
    live = EventStream.stream(pubsub, task_id, monitor: lookup(task_id))
           |> Stream.map(&to_stream_response(&1.payload))
    {:ok, Stream.concat([snapshot], live)}        # may replay one seen frame; never miss
end
```

Subscribing before reading the snapshot means an event landing in the gap is
seen twice (once in the snapshot fold, once live) rather than missed — acceptable
under the at-most-once/dedupe contract already documented. A **terminal** task
yields the snapshot frame and then a stream that halts immediately (the topic is
idle / the execution process already gone → `:DOWN` or no events).

> Note: `resubscribe/2` subscribes directly rather than passing an already-open
> subscription into `EventStream`, because the snapshot must be read *after*
> subscribing but *before* the live stream is enumerated. To keep a single
> subscription, `EventStream` accepts a `subscribe?: false` option so the caller
> owns subscribe/unsubscribe when it must interleave a store read. `send_message*`
> use the default (`EventStream` owns the subscription).

### Configurable idle timeout

- **Server default:** `A2A.Server` handle gains `drain_timeout: timeout()`
  (`non_neg_integer() | :infinity`), default **`:infinity`**, set via
  `A2A.Server.Supervisor` options and stored on the handle.
- **Per-request override (SDK-side, non-wire):** `send_message/2` accepts an
  optional third argument — a keyword `opts` with `:drain_timeout`. This is a
  *local blocking-wait budget*, not agent-to-agent protocol data, so it lives
  **outside** the proto `SendMessageConfiguration` (whose fixed proto fields are
  left untouched, per "proto is the authority for shapes").
- **Streaming:** always `:infinity` (a client holds the connection and can
  disconnect; a quiet long-running task must not be force-closed).

Precedence: per-request `:drain_timeout` (if given) → server handle default →
`:infinity`.

With execution-process monitoring in place, `:infinity` is a safe default:
crashes/exits terminate the stream deterministically via `:DOWN`; the idle
timeout only guards a pathological silent hang and is opt-in.

## `RequestHandler` surface

The callbacks were already declared in Phase 1 (`send_message_stream/2`,
`resubscribe/2` as `@optional_callbacks`). This phase implements them in
`DefaultHandler`. Signature notes:

- `send_message/2` stays; a new arity `send_message/3` (or an `opts`-defaulted
  head) carries the per-request `:drain_timeout`. The `RequestHandler`
  `@callback` for the blocking send is updated to reflect the optional opts.
- `resubscribe/2` takes the server handle + a resubscribe request (task id).
- No transport code; return types are `Enumerable.t()` (streaming) and
  `{:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}` (blocking).

## Error handling

- Unknown task on `resubscribe/2` → `{:error, A2A.Error.not_found(task_id)}`.
- Terminal-task continuation on `send_message*` → rejected as in Phase 1
  (`reject_terminal/2`, invariant 5).
- Execution `:DOWN` before a terminal frame: blocking resolves from the store
  projection (`failed` if the boundary persisted it) or returns an
  `:internal_error`; streaming simply ends (the last live frame, if any, was the
  terminal one; otherwise the stream completes without a synthetic error frame —
  transports later decide how to surface an abnormal end).
- Idle timeout (finite): blocking returns `{:error, %A2A.Error{code: :timeout}}`
  as in Phase 1; streaming never sets a finite idle timeout so this path is
  blocking-only.

## Testing strategy (TDD)

Everyday `mix test` stays green with no new toolchain. New tests under
`test/a2a/server/`.

- **`EventStream` unit:** yields events in publish order; emits then halts on a
  terminal event; halts on execution `:DOWN`; halts on a finite idle timeout
  and does *not* halt on `:infinity`; unsubscribes on halt (assert a
  post-halt broadcast is not received) and demonitors.
- **Blocking parity:** all existing `send_message/2` + `get_task/2` tests pass on
  the reshaped path (regression guard for the drain reshape).
- **Streaming — `send_message_stream/2`:** an `EchoExecutor` drives a frame
  sequence; assert the ordered `StreamResponse` frames; each frame round-trips
  through `A2A.JSON` (wire fidelity); the stream stops on terminal and on
  `input_required` but not on `auth_required`.
- **Resubscribe:** mid-flight attach → snapshot `task` frame followed by
  subsequent live frames; terminal task → snapshot-only, stream completes;
  unknown task → `not_found`; subscribe-before-snapshot ordering exercised (an
  event in the gap is seen, not missed).
- **Timeout:** `:infinity` default doesn't fire on a slow-but-live stream; a
  finite per-request `:drain_timeout` halts a silent stream and yields
  `:timeout`; per-request override beats the server default.
- **Property:** a random *valid* event sequence assembles (blocking) and projects
  (streaming) to codec-valid results (reuse Phase 1 `StreamData` generators).

## Documentation & housekeeping

- **New ADR** `0009-eventstream-termination.md`: the shared `EventStream` and its
  three-signal termination (terminal event | execution `:DOWN` | idle timeout),
  and why `:infinity` is the safe default. Add to the ADR README table.
- Update `docs/architecture/streaming-and-events.md`: snapshot-frame catch-up
  detail, monitor-based termination, `EventStream` as the shared source.
- Update `docs/architecture/request-handling.md` (or the relevant handler doc):
  the SDK-side `:drain_timeout` option and its precedence.
- Update `CLAUDE.md` server-runtime paragraph and `README.md` status line to note
  streaming has landed.
- No edits to existing ADRs; ADR-0009 is additive.

## Related

- [Phase 1 design](2026-08-29-server-core-phase1-design.md)
- [Architecture overview](../../architecture.md)
- [Streaming and events](../../architecture/streaming-and-events.md)
- [Transports](../../architecture/transports.md) (consumes this phase's frames later)
- [Process model](../../architecture/process-model.md)
- [Persistence](../../architecture/persistence.md)
- ADRs [0005](../../architecture/decisions/0005-pubsub-process-model.md),
  [0007](../../architecture/decisions/0007-ets-task-store.md), and new
  [0009](../../architecture/decisions/0009-eventstream-termination.md)
</content>
</invoke>
