# 9. EventStream — a shared subscription stream with three-signal termination

Date: 2026-08-30
Status: Accepted

## Context

Phase 1 consumed a task's events with a raw `receive` loop inside
`DefaultHandler.drain/1`. That loop only served the **blocking** `send_message/2`
and relied on the caller's process being the topic subscriber, with a hardcoded
30s *idle* timeout as its only termination safety net besides a terminal event.

Phase 2 adds **streaming** delivery (`send_message_stream/2`, `resubscribe/2`),
which needs the *same* event consumption — subscribe, receive envelopes in order,
stop at the end — but expressed as a lazy `Enumerable.t()` rather than a blocking
recursion. Rather than duplicate the receive logic per mode, both modes should
share one consumption primitive whose subscription lifecycle and termination
rules live in a single tested place.

The termination question also deserves a better answer than a blind idle timer.
An idle timeout cannot distinguish "the execution process crashed and no terminal
event will ever come" from "the process is alive and simply quiet" — it waits the
full timeout in both cases, and picking a value trades false-positives (killing a
slow-but-live task) against latency (hanging on a dead one).

## Decision

Introduce **`A2A.Server.EventStream`**, a `Stream.resource/3` that subscribes to a
task's PubSub topic on start, yields each `%A2A.Server.Events.Event{}` envelope,
and terminates on the **union of three signals**:

1. a **terminal event** — a `terminal?` envelope (terminal task state or
   `input_required`); the terminal event is yielded, then the stream halts;
2. **execution-process `:DOWN`** — the stream `Process.monitor`s the registered
   execution pid and halts deterministically the instant that process exits,
   whatever the reason;
3. an **idle timeout** — a `receive ... after` guard that halts after a
   configurable period of silence; `:infinity` disables it.

It unsubscribes and demonitors on halt (the `Stream.resource` after-fun), so a
consumer that stops early (a disconnected SSE client, an `Enum.take/2`) leaks
neither a subscription nor a monitor.

Both delivery modes consume it:

- **blocking** = `Enum.reduce_while/3` folding envelopes through
  `ResultAssembler` to the terminal `%Task{}`/`%Message{}`;
- **streaming** = `Stream.map/2` projecting each envelope to a
  `%A2A.Types.StreamResponse{}` frame.

Because `:DOWN` deterministically handles crashes/exits, the idle timeout is
demoted to defense-in-depth against a *silent hang* (a live process emitting
nothing) and **defaults to `:infinity`**. The blocking server default is
`:infinity`, overridable per request with an SDK-side `:drain_timeout` option;
streaming is always `:infinity`.

`auth_required` is deliberately **not** terminal (invariant 6): it does not set
the `terminal?` flag, so the stream stays open for out-of-band credential
injection and executor resumption.

## Consequences

- One subscription/termination implementation, tested once, serves blocking,
  streaming, and resubscribe; the raw `receive` in `DefaultHandler.drain/1` is
  deleted. The later push-notification sender can reuse the same raw-envelope
  stream.
- Crash handling is deterministic and prompt: a dead execution process ends the
  stream immediately via `:DOWN` instead of after an arbitrary idle wait. On a
  caught executor raise the execution boundary still persists `failed`, so a
  blocking caller reads the terminal task from the store even when it learns of
  the end via `:DOWN` rather than a terminal event.
- `:infinity` is a safe default *because* of the monitor: the common failure
  (crash/exit) is covered without a timer, and a real transport in front supplies
  its own request timeout for the residual silent-hang case.
- `EventStream` yields the **domain** envelope, not the wire `StreamResponse`, so
  it stays reusable by non-wire consumers; the wire projection lives only in the
  streaming path.
- Resubscribe interleaves a store read between subscribe and live enumeration, so
  `EventStream` supports a `subscribe?: false` mode letting the caller own the
  subscription; `send_message*` use the default where `EventStream` owns it.
- This ADR governs event *consumption*; it does not change the publisher
  (ADR-0005) or the store projection (ADR-0007). Resubscribe's catch-up remains a
  single folded-snapshot frame because the store is a projection, not an event
  log.
</content>
