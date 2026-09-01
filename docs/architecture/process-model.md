# Process model

[← Architecture](../architecture.md)

This is the heart of the Elixir SDK and where it diverges most from the Python
and JavaScript SDKs. Those SDKs hand-roll a concurrency core — an `EventTarget`/
`EventEmitter` bus, an async-generator bridge between push and pull, a
process-global map of per-task write-locks, and subscriber-eviction logic to
stop one dead consumer wedging the dispatcher. **In OTP, that machinery is
replaced by supervised processes, a `Registry`, and `Phoenix.PubSub`, and most
of its complexity simply disappears.**

Decision and rationale: [ADR-0005](decisions/0005-pubsub-process-model.md).

## Supervision tree

Everything is mountable into a host application's tree. Nothing is a global
singleton.

```
A2A.Supervisor
├── {Phoenix.PubSub, name: <configurable>}   # or reuse the host app's PubSub
├── Registry (unique keys: task_id → execution pid)
├── DynamicSupervisor (one transient child per running execution)
├── store owners (ETS-backed TaskStore / PushConfigStore, or user impls)
└── [if push_notifications: true]
    ├── Registry (unique keys: task_id → push dispatcher pid)
    └── DynamicSupervisor (one temporary PushDispatcher per task with ≥1 config)
```

- **`Phoenix.PubSub`** — fan-out of task events. Lightweight, no Phoenix
  dependency, no web coupling. The name is configurable so a Phoenix host passes
  its existing `MyApp.PubSub` and we start no extra process. See
  [ADR-0005](decisions/0005-pubsub-process-model.md).
- **`Registry`** — maps `task_id → execution pid`, enforcing one execution per
  task and enabling lookup for cancel/resubscribe.
- **`DynamicSupervisor`** — supervises execution processes; `:transient` children
  so a normal completion exits cleanly while a crash is restarted/reported.
- **Push registry + `DynamicSupervisor`** (opt-in, `push_notifications: true`)
  — a second, push-scoped `Registry`/`DynamicSupervisor` pair maps `task_id →
  A2A.Server.PushDispatcher` pid. One `:temporary` dispatcher runs per task
  that has ≥1 registered push config, started lazily on first registration
  via `PushDispatcher.Supervisor.ensure_started/2`. See
  [ADR-0012](decisions/0012-push-notifications.md).

## The execution process

When the request handler accepts a `SendMessage` that starts work, it starts a
**single process for that `task_id`** under the `DynamicSupervisor` and registers
it. The agent author's `AgentExecutor.execute/2` runs under that process.

Responsibilities of the execution process:

1. Build the `RequestContext` and a `TaskUpdater` bound to this task's topic.
2. Invoke the executor callback.
3. Broadcast every emitted event on the task's PubSub topic **and** persist it
   via the `TaskStore`.
4. On executor return, apply the terminal/interrupt state rules.
5. On crash, transition the task to `failed` (the supervisor observes the exit).

Because a process has a **serial mailbox**, it is the only writer of the task's
live state. The reference SDKs' global `taskWriteLocks` map that linearizes
concurrent writers is unnecessary — the mailbox *is* the lock, for free.

## Event fan-out

```
execution process ──broadcast──▶  "a2a:task:<task_id>"  (PubSub topic)
                                        │
              ┌─────────────────────────┼───────────────────────────┐
              ▼                         ▼                            ▼
        SSE plug conn            resubscribe conn              PushDispatcher
     (streaming client)        (reattached client)         (webhook delivery,
                                                          if push_notifications: true)
```

Any number of consumers subscribe to the topic. The SSE handler,
`SubscribeToTask`, and the per-task `A2A.Server.PushDispatcher` (started
lazily the first time a config is registered for that task — see
[ADR-0012](decisions/0012-push-notifications.md)) are all *just subscribers*
— none is privileged, none can write task state, and none blocks the executor.
Adding a consumer is `Phoenix.PubSub.subscribe/2`; there is no sink registry,
no back-pressure valve, no eviction — PubSub already handles a slow/dead
subscriber without stalling the producer. A hung or failing webhook delivery
is bounded (`push_timeout`) and logged, never raised — it affects only that
task's dispatcher, never the executor or another task's delivery.

## Lifecycle & state transitions

```
        SendMessage (new)
              │
              ▼
        ┌───────────┐   executor emits
        │ submitted │──────────────┐
        └───────────┘              ▼
                              ┌─────────┐
                    ┌─────────│ working │─────────┐
                    │         └─────────┘         │
      requires_input│           │                │ requires_auth
                    ▼           │                ▼
           ┌────────────────┐   │        ┌───────────────┐
           │ input_required │   │        │ auth_required │
           └───────┬────────┘   │        └──────┬────────┘
       resume via  │            │   resume via  │
        SendMessage│            ▼               │ out-of-band creds
                   └──▶ ┌──────────────────────────────┐
                        │ completed / failed / canceled│  (terminal, immutable)
                        │ / rejected                    │
                        └──────────────────────────────┘
```

- **`input_required`** and **`auth_required`** both leave the stream open — only
  a terminal task state closes it. The client resumes `input_required` by sending
  another `SendMessage` for the same task; `auth_required` resumes when the
  executor picks back up after credentials are injected out-of-band. See
  [ADR-0017](decisions/0017-streams-terminate-at-task-terminal.md).
- **Terminal states are immutable.** Once reached, the task is never mutated and
  the execution process exits normally.

## Cancellation

`CancelTask` looks the task up in the `Registry` and sends the execution
process a cancel message. The process invokes the executor's `cancel/2`
callback, lets it publish a final `:canceled` status, and exits. There is no
`asyncio.CancelledError`-style injection to reproduce; cancellation is an
ordinary message plus a clean exit. If the executor ignores cancellation, a
hard timeout escalates to `Process.exit/2`.

## Crash handling

An unhandled crash in the executor terminates the execution process. The
`DynamicSupervisor` observes the exit; the handler records a `failed` terminal
status for the task (with the error surfaced through telemetry — see
[Cross-cutting concerns](cross-cutting.md)). One task crashing never affects
another: isolation is per-process by construction.

## Resumption after node restart

Live execution state is in-process and does not survive a node restart — but the
`TaskStore` holds the durable projection, so task **history and terminal
results** survive. A restarted node serves `GetTask` from the store; a task
that was mid-flight when the node died is observable as its last persisted state.
The hot/cold split is detailed in [Persistence](persistence.md).

## Why this is simpler than the references

| Reference SDK mechanism | Elixir replacement |
| --- | --- |
| `EventTarget`/`EventEmitter` bus + Node polyfill | `Phoenix.PubSub` topic |
| async-generator push⇄pull bridge, `.return()`/`finally` cleanup | process mailbox + subscribe/unsubscribe |
| global per-task write-lock map | the execution process's serial mailbox |
| subscriber sink registry + `evict_on_full` | PubSub (slow subscriber can't stall producer) |
| `structuredClone` defensive copying everywhere | immutable data (free) |
| taskId→bus manager map for resubscribe | `Registry` |

## Related

- [Streaming and events](streaming-and-events.md) — event structs and push delivery.
- [Request handling](request-handling.md) — who starts the execution process.
- [ADR-0005](decisions/0005-pubsub-process-model.md),
  [ADR-0012](decisions/0012-push-notifications.md) (push dispatcher process).
