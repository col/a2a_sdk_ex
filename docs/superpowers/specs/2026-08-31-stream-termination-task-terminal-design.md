# Stream termination at task-terminal only

Date: 2026-08-31
Status: Approved (design)
Supersedes (in part): [ADR-0009](../../architecture/decisions/0009-eventstream-termination.md)

## Context

The A2A TCK reports one open failure, `STREAM-SUB-002` (MUST, spec §3.1.6), on
both the JSON-RPC and REST bindings:

> Stream closed but last event does not carry a terminal state

### What the TCK does

1. `SendMessage` with `messageId: tck-input-required…` → the task settles in
   `input_required`. The executor returns, so the `Execution` process **exits**.
2. `SubscribeToTask(id)` — the task is non-terminal, so the subscription is valid.
3. ~0.5s later, on a background thread, `SendMessage` with `tck-complete-task` and
   that `taskId` → a **new** execution completes the task.
4. The subscribe stream is expected to carry the `completed` event and then close.

### Root cause

`DefaultHandler.resubscribe_attach/3` looks the task up in the execution
`Registry`. At step 2 the first turn's execution has already exited, so the lookup
returns `[]` and the function unsubscribes and returns `{fresh_task, []}` — a
**snapshot-only** stream. It emits one `task` frame in `input_required` and closes,
before the follow-up in step 3 is even sent.

The defect is broader than that timing window. Our termination is **turn-scoped**
where the spec is **task-scoped**:

- `EventStream` halts on `%Event{terminal?: true}`, and `TaskUpdater.status/3`
  deliberately sets that flag for `:input_required` as well as the four terminal
  states (`task_updater.ex:124`).
- `EventStream` also halts on the monitored execution's `:DOWN` — and a follow-up
  turn is a *different* process.

So even had step 2 caught a live execution, the stream would have closed at that
turn's end rather than at task-terminal.

### What the spec actually requires

Three requirements, and they do not agree with each other by accident:

| Source | Rule |
| --- | --- |
| §3.1.6 (STREAM-SUB-002, MUST) | The `SubscribeToTask` stream "MUST terminate when the task reaches a terminal state (`completed`, `failed`, `canceled`, or `rejected`)". |
| §3.1.2 (Send Streaming Message) | "The stream MUST close when the task reaches a terminal state (e.g. completed, failed, canceled, rejected)." Identical rule. A `Message`-only stream is "exactly one `Message` object and then close immediately". |
| §3.2.2 (CORE-EXECUTION-MODE-001, MUST) | Blocking `SendMessage` "MUST wait until the task reaches a terminal state … **or an interrupted state (`input_required`, `auth_required`)**". |

So the two *streaming* paths share one rule — close at task-terminal — and only the
**blocking** path stops at interrupted states. Today we apply the blocking rule to
all three.

Two further gaps fall out of the same confusion:

- **`send_message_stream/2` is wrong, not just `resubscribe/2`.** It closes at
  `input_required` and on execution `:DOWN`, neither of which §3.1.2 sanctions.
  No TCK streaming test currently sends the `tck-input-required` prefix, so nothing
  passing today depends on the incorrect behaviour.
- **`auth_required` is missing from the blocking stop set.** `TaskUpdater.status/3`
  lists only `:input_required`. A blocking send to an agent that parks at
  `auth_required` waits for `drain_timeout`, which defaults to `:infinity` — it
  hangs forever. Latent today because no TCK scenario emits `auth_required`.
- **`PushDispatcher` stops at turn end** (`push_dispatcher.ex:35`), so a task that
  passes through `input_required` loses push delivery for every later turn.

## Decision

**Streams terminate at task-terminal only. The blocking call — not the stream —
owns the interrupted-state rule.**

There is no `halt_on:` mode and no second stream flavour. `EventStream` gets one
rule; the one consumer that needs to stop earlier already owns a stopping
mechanism (`Enum.reduce_while/3`) and uses it.

### `A2A.Server.Events`

Drop `Event.terminal?`. It is fully derivable from the payload, and its dual
meaning ("ends the blocking drain" vs "the task is over") is what caused the bug.
Replace it with one predicate:

```elixir
@spec final?(Event.payload()) :: boolean()
def final?(%Message{}), do: true                      # §3.1.2 pattern 1
def final?(%Task{} = t), do: ResultAssembler.terminal?(t)
def final?(%TaskStatusUpdateEvent{status: %{state: s}}), do: s in @terminal_states
def final?(%TaskArtifactUpdateEvent{}), do: false
```

`final?` means "this payload closes a stream": a terminal task state, or a bare
`Message` direct reply. One definition, one place, no envelope field to set
inconsistently.

### `A2A.Server.EventStream`

Halts on the union of:

1. an event where `Events.final?(payload)` — yielded, then halt;
2. the optional monitored pid going `:DOWN` (`:monitor` is now passed **only** by
   the blocking drain);
3. the idle timeout.

The moduledoc's "three-signal termination" story survives; signal 1 changes
meaning from turn-end to task-terminal, and signal 2 becomes opt-in rather than
universal.

### `A2A.Server.DefaultHandler`

- **`send_message/2`** — unchanged shape. `fold_event/2` gains the interrupted
  rule it should always have owned:

  ```elixir
  defp fold_event(%Event{payload: p}, {_, acc}) do
    if Events.final?(p) or interrupted?(p),
      do: {:halt, {:done, ResultAssembler.apply(acc, p)}},
      else: {:cont, {:running, ResultAssembler.apply(acc, p)}}
  end
  ```

  with `interrupted?/1` covering `:input_required` **and** `:auth_required`
  (§3.2.2). Note this is a plain function call, not a guard — the existing
  clause-per-case shape gives way to one clause with a body decision, since
  neither predicate is guard-safe. The `%Message{}` clause and the `:monitor`
  option stay as they are —
  the monitor still guards the case where the `Execution` GenServer itself dies
  without emitting anything.

- **`send_message_stream/2`** — drops `monitor: pid`. Plain `EventStream` with
  `idle_timeout: server.stream_idle_timeout`. It now stays open through
  `input_required` and `auth_required` and closes at terminal, per §3.1.2.

- **`resubscribe/2`** — `resubscribe_attach/3` is **deleted**. `subscribe_live/3`
  keeps the terminal-task rejection (§3.1.6) and then unconditionally returns
  snapshot + live stream:

  ```elixir
  {:ok, Stream.concat([StreamResponse.task(task)], live_stream(server, task_id))}
  ```

  No `Registry.lookup`, no stale-snapshot re-read. That whole hazard — the task
  settling between the store read and the registry lookup — disappears: we
  subscribe *before* reading the snapshot and now stay subscribed, so the terminal
  event arrives on the live stream instead of being discarded by an unsubscribe.

### `A2A.Server.PushDispatcher`

Stops on `Events.final?(payload)` instead of the envelope flag. A dispatcher now
survives `input_required` and keeps delivering across later turns, bounded by its
existing 60s idle timeout.

### New configuration: `stream_idle_timeout`

Once neither streaming path closes at `input_required`, a stream for a task parked
awaiting input stays open indefinitely — and `A2A.Plug.SSE` only detects a client
disconnect when it tries to `chunk/2`, so with no events there is nothing to detect
it with. Today the `:DOWN` monitor bounds this by accident.

Add `stream_idle_timeout` to `%A2A.Server{}` alongside `drain_timeout`, threaded
through `A2A.Server.Supervisor`, **defaulting to `300_000` (5 minutes)**. Both
streaming paths pass it as `EventStream`'s `idle_timeout`.

This is spec-safe: the timeout only fires after a period of total silence on the
task, so it can never truncate a stream that is actively delivering events. A
client that still cares resubscribes. `drain_timeout` keeps its `:infinity`
default and its per-request override.

### Invariant 6 simplifies

`docs/architecture.md` invariant 6 currently reads *"`auth_required` does not
terminate a stream (unlike other non-working states)"*. Under the new rule
`auth_required` stops being a special case; it becomes:

> **Only terminal task states terminate a stream.** Interrupted states
> (`input_required`, `auth_required`) return control to a *blocking* caller while
> the stream stays open and the execution remains resumable.

## Consequences

- `STREAM-SUB-002` passes on both bindings; the compliance report's one open MUST
  failure clears.
- The `Event` envelope loses a field and `TaskUpdater` loses the comment block
  explaining why its terminal set differs from `ResultAssembler`'s. Net less code
  than today, not more.
- **Behaviour change for SDK users:** `send_message_stream/2` no longer ends at
  `input_required`. An agent that asks for input keeps the stream open; the client
  reads the `input_required` status update, sends its follow-up as a separate
  request, and the next turn's events arrive on the original stream. This is what
  §3.1.2 prescribes, but it is a visible change and belongs in CHANGELOG.
- **Plug-level tests must arrange for termination.** `A2A.Plug.RESTTest`'s
  `POST /tasks/:id:subscribe` test (rest_test.exs:182) relies on the stream closing
  immediately after the snapshot; `Router.call/2` is synchronous, so under the new
  rule it would block for the full idle timeout. Those tests pass a short
  `stream_idle_timeout` to `ServerSupervisor` (they already start their own tree
  per test) or arrange a terminal event.
- A hard kill of an `Execution` GenServer (supervisor shutdown, `Process.exit/2`)
  no longer ends attached streams promptly — they wait out the idle timeout. A
  crashing *executor* is unaffected: `Execution.handle_info/2` (execution.ex:52)
  converts an abnormal child exit into a `failed` terminal broadcast.
- Push delivery keeps working across a multi-turn task instead of stopping at the
  first `input_required`.

## Testing strategy

TDD throughout; every item is a failing test first. `mix test` must stay green
with no proto toolchain, and `mix precommit` gates the branch.

1. **`test/a2a/server/event_stream_test.exs`** — halts on each terminal state and
   on a `%Message{}` payload; does **not** halt on `input_required` or
   `auth_required`; still halts on `:DOWN` when `:monitor` is passed and on the
   idle timeout.
2. **`test/a2a/server/streaming_test.exs`**
   - *Regression for STREAM-SUB-002:* resubscribe to a task parked in
     `input_required` with **no live execution**, then send a follow-up that
     completes it — assert the stream yields the snapshot, then the follow-up
     turn's frames, and closes with a terminal frame last.
   - Rewrite `"streaming does not stop on auth_required but stops on
     input_required"` (line 72) to assert the stream survives **both** and closes
     only at terminal.
   - Keep the existing live-execution resubscribe test; it should still pass.
3. **`test/a2a/server/multi_turn_test.exs` / blocking path** — existing
   `input_required` return is covered; add `auth_required` returns the task rather
   than hanging (guarded by a short `drain_timeout` so a regression fails fast
   instead of hanging the suite).
4. **`test/a2a/server/push_dispatcher_test.exs`** — the dispatcher survives an
   `input_required` event and delivers a later turn's terminal event.
5. **`test/a2a/plug/rest_test.exs`, `sse_test.exs`** — short `stream_idle_timeout`
   in setup; assert the subscribe response still streams the snapshot frame.
6. **`task_updater_test.exs`, `events_test.exs`, `execution_test.exs`** — update
   the `terminal?:` assertions to the new envelope shape.

## Documentation

- **New ADR-0017**, "Streams terminate at task-terminal only", superseding
  ADR-0009 in part (ADRs are immutable per `decisions/README.md`; 0009's Status
  line becomes `Superseded in part by 0017` and the README table is updated).
- `docs/architecture.md` — invariant 6 rewritten as above.
- `docs/architecture/streaming-and-events.md` — the "do not stop on
  `auth_required`" note generalises to the single rule.
- `docs/architecture/process-model.md` (lines ~103–117) and
  `request-handling.md` (lines ~43, 70, 130) — the state diagram and the
  `requires_auth/2` / `requires_input/2` rows.
- `CLAUDE.md` — the streaming paragraph and the known-constraints list.
- `CHANGELOG` entry for the `send_message_stream/2` behaviour change and the new
  `stream_idle_timeout` option.

## Out of scope

- **SSE heartbeat frames** (`: ping\n\n`) to detect client disconnects promptly.
  The correct long-term answer to connection liveness, but a separate change to
  `A2A.Plug.SSE` with its own framing and interval decisions.
- **gRPC binding** — `STREAM-SUB-002` skips on `grpc`; we do not ship that
  transport.
- The globally-named `TaskStore.ETS` / `PushConfigStore.ETS` limitation, which
  constrains how these tests are written but is unchanged by this work.
