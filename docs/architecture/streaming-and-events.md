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
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                     ▼
   live SSE stream     resubscribe          Push.Sender
   (message/stream)    (tasks/resubscribe)  (webhook POST)
```

## Live streaming (SSE)

`message/stream` opens an SSE response that subscribes to the topic and streams
each event as it is published (see [Transports](transports.md#sse-streaming-a2aplugsse)
for the header-peek and chunking details).

Termination rules (ported explicitly from the reference SDKs):

- Stop on a **terminal** state (`completed`/`failed`/`canceled`/`rejected`).
- Stop on **`input_required`**.
- **Do not** stop on **`auth_required`** — the executor may resume after
  out-of-band credential injection. This asymmetry is intentional and matches
  the JS SDK.

## Resubscription

`tasks/resubscribe` is simply a new SSE subscription to an **already-live**
topic. It works because the execution process outlives any single consumer
(invariant 2 in the [top-level doc](../architecture.md)): a client that dropped
its stream — or a *different* client entirely — can attach and receive
subsequent events. The reference SDKs need a `taskId → bus` manager map to make
this possible; here the `Registry` + PubSub topic provide it directly.

Events emitted *before* a resubscription are read from the `TaskStore`
projection ([Persistence](persistence.md)); events after it arrive live over the
topic.

## Push notifications (webhooks)

For clients that cannot hold an SSE stream open (serverless, mobile,
long-running batch), A2A supports webhook delivery. This is a **should-have**
feature included in v1 — see [Scope and roadmap](scope-and-roadmap.md).

Flow:

1. Agent advertises `capabilities.push_notifications = true` on its card.
2. Client registers a `TaskPushNotificationConfig` (webhook URL + optional
   token) via `tasks/pushNotificationConfig/set`; it is saved in the
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
