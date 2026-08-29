# Architecture

This document is the high-level map of the A2A Elixir SDK (`a2a`). It follows
the [`ARCHITECTURE.md` convention](https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html):
a bird's-eye view that names the major components, states the boundaries and
invariants, and links out to detailed documents rather than trying to be
exhaustive itself.

If you are looking for **why** a particular choice was made, jump to the
[Architecture Decision Records](architecture/decisions/README.md).

## What this library is

`a2a` is an Elixir SDK for building **A2A servers** — agentic applications that
expose their capabilities over the [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/v1.0.0/specification/).
It lets you implement your agent's logic once and serve it, spec-compliant, over
standard web transports, with first-class streaming, cancellation, resumption,
and webhook delivery built on OTP.

It is a **peer** of the official [Python](https://github.com/a2aproject/a2a-python)
and [JavaScript](https://github.com/a2aproject/a2a-js) SDKs — same protocol,
same architectural seams — but deliberately **not** a line-by-line port. The
concurrency core those SDKs hand-roll (an event bus, an async-generator bridge,
per-task write-locks, subscriber eviction) is exactly what OTP provides for
free, so that layer is re-designed around processes, `Registry`, and
`Phoenix.PubSub` rather than translated. See
[Process model](architecture/process-model.md) for the heart of this.

## Scope (v1)

- **Server side only.** Hosting an agent. The client side is deferred.
- **A2A protocol v1.0 only.** No v0.3 backward-compatibility layer.
- **Two transports:** JSON-RPC and HTTP+JSON/REST, behind one transport-agnostic
  request handler. gRPC is deferred but the handler boundary is designed for it.

The full must/should/deferred breakdown, and the reasoning, live in
[Scope and roadmap](architecture/scope-and-roadmap.md).

## The seven seams

The A2A protocol has a stable shape that both reference SDKs express as
interfaces/abstract base classes. In Elixir these become **behaviours** —
the extension points you implement or swap:

| Seam | Elixir form | Responsibility |
| --- | --- | --- |
| Agent logic | `A2A.Server.AgentExecutor` behaviour | Your code. Receives a request context, emits events. |
| Protocol orchestration | `A2A.Server.RequestHandler` behaviour + `DefaultHandler` | Routes RPCs, runs executions, drains events, persists. |
| Event streaming | per-task `Phoenix.PubSub` topic | Fan-out of task/status/artifact events to all consumers. |
| Task persistence | `A2A.Server.TaskStore` behaviour | Durable projection of task state (ETS default). |
| Push config persistence | `A2A.Server.PushConfigStore` behaviour | Stored webhook configs (ETS default). |
| Wire transport | `A2A.Plug.Router` | JSON-RPC + REST + SSE over Plug. |
| Identity | `A2A.User` + `user_resolver` hook | Surfaces the authenticated caller to the executor. |

## Container view (C4 level 2)

```
                         ┌──────────────────────────────────────────────┐
   A2A client            │  Host application (Phoenix / Plug / Bandit)   │
  (Python/JS/…)          │                                              │
        │                │   ┌────────────────────────────────────┐     │
        │  HTTP           │   │  A2A.Plug.Router  (mounted/forward) │     │
        ├────────────────┼──▶│  JSON-RPC · REST · SSE · AgentCard   │     │
        │                │   └───────────────┬────────────────────┘     │
        │                │                   │ delegates                 │
        │                │        ┌──────────▼───────────┐               │
        │                │        │ A2A.Server.RequestHandler            │
        │                │        │ (DefaultHandler)      │               │
        │                │        └───┬─────────┬────────┬┘               │
        │                │  spawns    │ subscribes │ persists            │
        │                │  ┌─────────▼──┐   ┌───▼────────┐  ┌──────────┐ │
        │                │  │ Execution  │   │ PubSub      │  │TaskStore │ │
        │  webhook POST   │  │ process    │──▶│ task topic  │  │(ETS)     │ │
        │◀───────────────┼──│ (your      │   └───┬────────┘  └──────────┘ │
        │  (push notif)   │  │  Executor) │       │ subscribers            │
        │                │  └────────────┘   ┌───▼──────┐ ┌────────────┐  │
        │                │                   │ SSE conn │ │ Push.Sender│  │
        │                │                   └──────────┘ └────────────┘  │
        │                │                                              │
        │                │   A2A.Supervisor: PubSub · Registry ·         │
        │                │   DynamicSupervisor · store owners            │
        │                └──────────────────────────────────────────────┘
```

## Codemap

Where things live (planned module namespaces):

- `A2A.Types.*` — domain structs: `Message`, `Task`, `Part`, `Artifact`,
  `AgentCard`, `TaskStatus`, update events, enums. Hand-written, idiomatic.
  → [Data model](architecture/data-model.md)
- `A2A.JSON` — the proto3-JSON codec (camelCase mapping, enum⇄atom,
  large-int-as-string, base64 bytes). Owns wire fidelity.
  → [Data model](architecture/data-model.md)
- `A2A.Server.AgentExecutor` / `RequestContext` / `TaskUpdater` — the surface an
  agent author implements and the ergonomic helper they emit events through.
  → [Request handling](architecture/request-handling.md)
- `A2A.Server.RequestHandler` / `DefaultHandler` — protocol orchestration.
  → [Request handling](architecture/request-handling.md)
- `A2A.Server.Execution.*` — the per-task process, its `DynamicSupervisor`, and
  the `Registry` mapping `task_id → pid`.
  → [Process model](architecture/process-model.md)
- `A2A.Server.Events` — PubSub topic conventions and event structs.
  → [Streaming and events](architecture/streaming-and-events.md)
- `A2A.Server.TaskStore` / `PushConfigStore` — persistence behaviours + ETS
  defaults. → [Persistence](architecture/persistence.md)
- `A2A.Server.Push.Sender` — webhook delivery.
  → [Streaming and events](architecture/streaming-and-events.md)
- `A2A.Plug.*` — `Router`, `JSONRPC`, `REST`, `AgentCard`, `SSE`; and
  `A2A.Standalone` for a zero-framework Bandit boot.
  → [Transports](architecture/transports.md)
- `A2A.Extensions`, `A2A.User`, `A2A.Telemetry`, `A2A.Error` — cross-cutting.
  → [Cross-cutting concerns](architecture/cross-cutting.md)

## Invariants

These hold across the system; violating them is a bug:

1. **One execution process per `task_id`.** The `Registry` enforces uniqueness;
   its serial mailbox is the only writer of a task's live state, which is why no
   cross-request lock is needed.
2. **The execution process outlives any single consumer.** SSE disconnects and
   `resubscribe` attach/detach freely; the execution is driven by the executor's
   lifecycle, not the consumer's. This is what makes resumption work.
3. **Events flow one way:** executor → `TaskUpdater` → PubSub topic → consumers.
   Consumers never write task state.
4. **The `TaskStore` is a projection, not the source of truth for running
   tasks.** Live/hot state is in the process; the store is the durable *cold*
   record (history, terminal tasks, restart recovery). See
   [Persistence](architecture/persistence.md).
5. **Terminal task states are immutable.** Once `completed`/`failed`/`canceled`/
   `rejected`, a task is never mutated.
6. **`auth_required` does not terminate a stream** (unlike other non-working
   states) — the executor may resume after out-of-band credential injection.
7. **Nothing global is assumed.** PubSub name, stores, and hooks are passed at
   init so the whole tree mounts inside a host application's supervision tree.

## Detailed documents

- [Data model](architecture/data-model.md)
- [Process model](architecture/process-model.md)
- [Request handling](architecture/request-handling.md)
- [Transports](architecture/transports.md)
- [Streaming and events](architecture/streaming-and-events.md)
- [Persistence](architecture/persistence.md)
- [Cross-cutting concerns](architecture/cross-cutting.md)
- [Scope and roadmap](architecture/scope-and-roadmap.md)
- [Architecture Decision Records](architecture/decisions/README.md)

## Documentation conventions

This doc set follows widely-used, tool-agnostic conventions so it stays legible
to contributors and publishes cleanly to HexDocs:

- The top file is a [matklad-style `ARCHITECTURE.md`](https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html)
  map; detail files hold the depth.
- Diagrams are described at [C4](https://c4model.com/) Context/Container/Component
  zoom levels (ASCII here; no tooling required to read them).
- Decisions are captured as [ADRs](https://github.com/joelparkerhenderson/architecture-decision-record)
  (Michael Nygard's Context/Decision/Consequences format), one file each.
- Every file under `docs/` is plain Markdown so it can be listed in ExDoc
  `extras` and rendered on HexDocs as a guide.
