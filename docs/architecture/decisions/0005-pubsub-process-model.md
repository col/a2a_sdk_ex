# 5. Process-per-task + Phoenix.PubSub for the concurrency core

Date: 2026-08-29
Status: Accepted

## Context

A2A servers run long-lived, streaming task executions that multiple consumers
attach to: a live SSE stream, a later `tasks/resubscribe`, and a push-
notification sender, potentially at once. The reference SDKs hand-roll this in a
runtime without lightweight processes: an `EventTarget`/`EventEmitter` bus (with
a Node polyfill), an async-generator bridge between push and pull, a process-
global map of per-task write-locks to serialize concurrent writers, and
subscriber-eviction logic so one dead consumer can't wedge the dispatcher.

OTP provides supervised processes, `Registry`, and message passing natively.
`Phoenix.PubSub` is a small, standalone library (no Phoenix or web coupling; the
default `:pg` adapter has no runtime deps) that gives topic-based fan-out.

## Decision

Model each task execution as **one supervised process** (under a
`DynamicSupervisor`, keyed in a `Registry` by `task_id`), publishing events on a
per-task **`Phoenix.PubSub`** topic that any number of consumers subscribe to.
The PubSub name is configurable so a Phoenix host reuses its existing PubSub.

## Consequences

- The reference SDKs' bus, async-generator bridge, global write-lock, and sink-
  eviction machinery **disappear**: the process mailbox serializes writes, PubSub
  handles fan-out and slow subscribers, and immutability makes defensive copying
  free (see the comparison table in [Process model](../process-model.md)).
- `tasks/resubscribe` and multi-consumer delivery are trivial — attach another
  subscriber to a live topic.
- Cancellation is an ordinary message + clean process exit, not an exception
  injected into a coroutine.
- One new dependency, `phoenix_pubsub`. It is lightweight and, by being
  configurable, actively *eases* embedding into an existing Phoenix app rather
  than fighting it.
- Live execution state is in-process and does not survive a node restart; the
  durable projection lives in the [`TaskStore`](../persistence.md)
  ([ADR-0007](0007-ets-task-store.md)).
