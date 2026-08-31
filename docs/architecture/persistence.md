# Persistence

[← Architecture](../architecture.md)

## Decision in brief

Define two persistence **behaviours** — `A2A.Server.TaskStore` and
`A2A.Server.PushConfigStore` — and ship **ETS-backed defaults** for both. A
first-party Ecto/Postgres adapter is a documented fast-follow package, not part
of core v1. Rationale: [ADR-0007](decisions/0007-ets-task-store.md).

## Hot vs cold state

The most important idea on this page, and a genuine departure from the reference
SDKs: **in Elixir the "task store" is a projection, not the source of truth for
running tasks.**

- **Hot state** — a running task's live status, in-flight artifacts, current
  history — lives in its [execution process](process-model.md). It is fast,
  serialized by the process mailbox, and never contended.
- **Cold state** — the durable record used for `GetTask`, `ListTasks`,
  resubscription catch-up, and recovery after a node restart — lives in the
  `TaskStore`. The execution process writes through to it as events are emitted.

So the store is updated *from* the event stream; it is the persistent shadow of
what the process already knows. `GetTask` for a *running* task can be served
from either (they agree); for a *finished* task it comes from the store.

This split means the store's job is simpler than in Python/JS: it is not a
concurrency-control point (the process is), just durable storage.

## `A2A.Server.TaskStore` behaviour

```elixir
@callback save(task :: A2A.Types.Task.t(), scope :: A2A.Scope.t()) :: :ok | {:error, term}
@callback get(task_id :: String.t(), scope :: A2A.Scope.t()) :: {:ok, A2A.Types.Task.t()} | {:error, :not_found}
@callback list(params :: map(), scope :: A2A.Scope.t()) :: {:ok, A2A.Types.TaskList.t()} | {:error, term}
@callback delete(task_id :: String.t(), scope :: A2A.Scope.t()) :: :ok | {:error, term}
```

- **Scope** carries tenant + owner, derived from the authenticated
  [`User`](cross-cutting.md) via an owner resolver, so multi-tenant deployments
  filter rows by caller. Single-tenant agents get a default scope and can ignore
  it.
- `list/2` supports filtering (by context, state, timestamp), descending sort,
  and cursor pagination — matching the reference stores.

### Default: `A2A.Server.TaskStore.ETS`

An ETS table owned by a process in the [supervision tree](process-model.md).
Concurrent-read friendly, survives across request processes, and needs no
external dependency. Suitable for development and for production agents whose task
history need not survive a restart.

## `A2A.Server.PushConfigStore` behaviour

```elixir
@callback set(config :: A2A.Types.TaskPushNotificationConfig.t(), scope) :: {:ok, config} | {:error, term}
@callback get(task_id :: String.t(), id :: String.t(), scope) :: {:ok, config} | {:error, :not_found}
@callback list(task_id :: String.t(), scope) :: {:ok, [config]}
@callback delete(task_id :: String.t(), id :: String.t(), scope) :: :ok | {:error, term}
```

ETS default, scoped identically. Consumed by
[`Push.Sender`](streaming-and-events.md#push-notifications-webhooks).

## Behaviour conformance testing

Because the store is a swappable behaviour, we ship a **shared conformance test
suite** any implementation can run (`use A2A.Server.TaskStore.ConformanceCase`).
The ETS default runs it; a future Ecto adapter runs the same suite. This keeps
third-party and first-party adapters honest against one contract.

## The Ecto adapter (deferred)

A first-party `a2a_ecto` package is planned as a fast-follow, once the behaviour
has proven itself against a real agent — see
[Scope and roadmap](scope-and-roadmap.md) and
[ADR-0007](decisions/0007-ets-task-store.md). Deferring it avoids baking schema
and migration decisions in before the interface is settled. Because persistence
is a behaviour from day one, dropping in Ecto/Postgres later requires no change
to the handler or execution model. The reference Python SDK's configurable table
names and optional field encryption are noted as design inputs for that adapter.

## Related

- [Process model](process-model.md) — where hot state lives.
- [Streaming and events](streaming-and-events.md) — push config consumer, resubscribe catch-up.
- [ADR-0007](decisions/0007-ets-task-store.md).
