# 17. Streams terminate at task-terminal only

Date: 2026-08-31
Status: Accepted

## Context

[ADR-0009](0009-eventstream-termination.md) gave `EventStream` a single
termination rule shared by all three consumers: halt on a `terminal?` envelope,
where `TaskUpdater` set that flag for the four terminal states **and** for
`input_required`. That conflated two different rules the spec keeps apart:

- §3.1.2 and §3.1.6 give both *streaming* operations the same rule — the stream
  closes when the **task** reaches a terminal state (`completed`, `failed`,
  `canceled`, `rejected`), or after a single direct `Message` (§3.1.2 pattern 1).
- §3.2.2 gives the *blocking* send a different one — it returns at a terminal
  state **or** an interrupted state (`input_required`, `auth_required`).

TCK `STREAM-SUB-002` (MUST) failed on both bindings as a result. `SubscribeToTask`
on a task parked at `input_required` — the first turn's execution already exited —
found nothing in the execution `Registry`, returned a snapshot-only stream, and
closed before the follow-up turn was even sent. Even with a live execution it
would have closed at that turn's end, via the flag or via the `:DOWN` monitor.

Two further defects shared the cause: `send_message_stream/2` closed at
`input_required` (§3.1.2 says terminal), and `PushDispatcher` shut down there too,
losing push delivery for every later turn of a multi-turn task.

## Decision

**Streams terminate at task-terminal only. The blocking call — not the stream —
owns the interrupted-state rule.**

- `Event.terminal?` is deleted. Stream-closing is derived from the payload by one
  predicate, `Events.final?/1`: a terminal task state, or a `%Message{}`.
- `EventStream` halts on `final?/1`, on an optional monitored `:DOWN`, or on an
  idle timeout. `:monitor` is now passed **only** by the blocking drain — a stream
  outlives any single turn's process.
- `DefaultHandler.fold_event/2` halts on `final?/1` **or** an interrupted status
  (`input_required`, `auth_required`), which also fixes a latent hang: a blocking
  send to an agent parking at `auth_required` previously waited out `drain_timeout`,
  which defaults to `:infinity`.
- `resubscribe/2` drops its `Registry` lookup and always returns snapshot + live
  stream. The old "settle between the store read and the registry lookup" hazard
  disappears with it: we subscribe before reading the snapshot and stay subscribed.
- `PushDispatcher` stops on `final?/1`.
- New `stream_idle_timeout` (default `300_000`) bounds a stream on a parked task,
  since `A2A.Plug.SSE` can only detect a disconnect when it next writes a chunk.

Invariant 6 in [the top-level doc](../../architecture.md) generalises: it no longer
singles out `auth_required`, because **only terminal task states terminate a stream**.

## Consequences

- `STREAM-SUB-002` passes on both bindings.
- **Behaviour change:** `send_message_stream/2` no longer ends at `input_required`.
  An agent that asks for input keeps the stream open; the client reads the
  `input_required` status update, answers on a separate request, and the next
  turn's events arrive on the original stream. This is what §3.1.2 prescribes.
- Less code than before: the envelope loses a field, `TaskUpdater.emit/3` loses an
  argument, and `resubscribe_attach/3` is deleted outright.
- A hard kill of an `Execution` GenServer no longer ends attached streams promptly;
  they wait out `stream_idle_timeout`. A crashing *executor* is unaffected —
  `Execution` converts an abnormal child exit into a `failed` terminal broadcast.
- Plug-level tests that subscribe to a parked task must pass a short
  `stream_idle_timeout`, since `Plug.Router.call/2` is synchronous.
- **Push delivery survives an `input_required`, but only within the dispatcher's
  60s idle window.** `PushDispatcher` no longer stops at the end of a turn, so a
  client that answers promptly keeps receiving. It is still bounded by its
  hardcoded 60s idle timeout and is only (re)started by `ensure_dispatcher/2` on a
  config registration, so a task parked longer than 60s loses its dispatcher and a
  later turn delivers nothing until a config is registered again. Per-turn
  dispatcher revival is separate work; a receiver that needs the full history
  reconciles via `GetTask`.

Supersedes [ADR-0009](0009-eventstream-termination.md) in part: the shared
`EventStream` primitive, its subscription lifecycle, and the idle-timeout
defense-in-depth all stand; only the meaning of signal 1 (and the scope of
signal 2) changes.
