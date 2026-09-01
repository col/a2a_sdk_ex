# Streaming and events

[← Architecture](../architecture.md)

This document covers the event model that flows over a task's PubSub topic, and
the two ways it reaches a client: **live streaming** (SSE / resubscribe) and
**push notifications** (webhooks).

## Event structs

The executor emits, and consumers receive, these event structs (mirrors of the
wire events — see [Data model](data-model.md)):

| Event | Meaning |
| --- | --- |
| `Task` snapshot | Start-of-work / current full state |
| `Message` | A direct message reply (non-task interaction) |
| `TaskStatusUpdateEvent` | State transition, optional message, `final?` flag |
| `TaskArtifactUpdateEvent` | Artifact produced; `append?` + `last_chunk?` for chunked output |

On the wire these are wrapped in a tagged `StreamResponse`
(`task | message | status_update | artifact_update`).

## The task topic

Every task has a PubSub topic, `"a2a:task:<task_id>"`. The
[execution process](process-model.md) is the sole publisher; everything else
subscribes. This single mechanism serves all three delivery paths:

```
                          "a2a:task:<task_id>"
                                    │
             ┌──────────────────────┼──────────────────┐
             ▼                      ▼                  ▼
      live SSE stream          resubscribe        Push.Sender
  (SendStreamingMessage)    (SubscribeToTask)   (webhook POST)
```

## Live streaming (SSE)

`SendStreamingMessage` opens an SSE response that subscribes to the topic and streams
each event as it is published (see [Transports](transports.md#sse-streaming-a2aplugsse)
for the header-peek and chunking details). At the `DefaultHandler` level, before
any transport exists, `send_message_stream/2` returns this directly as an
`Enumerable.t()` of `%A2A.Types.StreamResponse{}` frames.

Both live streaming and resubscribe are served by the **same** consumption
primitive, `A2A.Server.EventStream` — a `Stream.resource/3` that subscribes to
the task topic and yields envelopes until it halts. Stream termination is the
union of three signals, not just a terminal event:

1. a **final** event — one whose payload closes a stream per `Events.final?/1`: a
   terminal task state (`completed`/`failed`/`canceled`/`rejected`), or a direct
   `Message` reply (§3.1.2 pattern 1);
2. the execution process going **`:DOWN`** — opt-in via `:monitor`, and passed only
   by the blocking drain, since a stream outlives any single turn's process;
3. an **idle timeout** — `stream_idle_timeout` (default 5 minutes) for streaming,
   `drain_timeout` (default `:infinity`, per-request overridable) for blocking.

**Do not** stop a stream on an **interrupted** state (`input_required`,
`auth_required`). Those end a *blocking* caller's wait (§3.2.2) — the rule lives in
`DefaultHandler.fold_event/2` — while the stream stays open for the next turn or
for out-of-band credential injection. See
[ADR-0017](decisions/0017-streams-terminate-at-task-terminal.md).

## Resubscription

`SubscribeToTask` is simply a new SSE subscription to the task's topic, live or
not: the topic is keyed by task id and outlives any single turn's execution
process, so `resubscribe/2` no longer needs to find a live execution to attach
to — it just subscribes. A client that dropped its stream — or a *different*
client entirely — can attach at any point, including after the task has parked
at `input_required`/`auth_required` between turns, and receive subsequent
events. The reference SDKs need a `taskId → bus` manager map to make this
possible; here the PubSub topic provides it directly.

`resubscribe/2` also consumes `A2A.Server.EventStream` (with `subscribe?: false`,
since it owns the subscription itself to interleave it with a store read —
subscribe first, then read the snapshot, so an event landing in the gap is seen
live rather than missed). Catch-up for everything emitted *before* the
resubscription is a **single folded-snapshot `task` frame** read from the
`TaskStore` projection ([Persistence](persistence.md)) — not a replay of
individual past events, because the store is a projection, not an event log.
Events after the snapshot arrive live over the topic, subject to the same
three-signal termination as live streaming.

## Push notifications (webhooks)

For clients that cannot hold an SSE stream open (serverless, mobile,
long-running batch), A2A supports webhook delivery. This is a **should-have**
feature included in v1 — see [Scope and roadmap](scope-and-roadmap.md).

Flow:

1. Agent advertises `capabilities.push_notifications = true` on its card.
2. Client registers a `TaskPushNotificationConfig` (webhook URL + optional
   token) via `CreateTaskPushNotificationConfig`; it is saved in the
   `PushConfigStore` ([Persistence](persistence.md)).
3. `A2A.Server.Push.Sender` subscribes to the task topic like any other
   consumer and **POSTs each `StreamResponse`** to the registered URL, including
   the notification token header for the receiver to verify.

Design notes:

- The sender is *just another subscriber* — no special code path in the
  execution process, no coupling to streaming. Delivery happens in parallel with
  (or instead of) a live SSE stream.
- The HTTP client is pluggable (default `Req` if available); delivery runs in a
  supervised task so a slow or failing webhook never blocks the executor or other
  consumers.
- Retry/back-off policy is a sender concern and configurable.

## Ordering & delivery guarantees

- Within a task, the execution process publishes events **in order**; PubSub
  preserves per-topic ordering to each subscriber, so a single consumer sees a
  consistent event sequence.
- Delivery to live subscribers is best-effort at-most-once (a disconnected SSE
  client misses events until it resubscribes and reads the store projection to
  catch up).
- Webhook delivery is at-least-once under retry; receivers should be idempotent
  on `task_id` + event identity.

## Related

- [Process model](process-model.md) — who publishes events.
- [Persistence](persistence.md) — the durable projection resubscribers catch up from.
- [Transports](transports.md) — SSE mechanics.
