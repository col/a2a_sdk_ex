# Scope and roadmap

[← Architecture](../architecture.md)

This document records what v1 includes, what it defers, and why — the boundary
that keeps the first release shippable and coherent. Each decision links to its
ADR.

## v1 scope at a glance

| Dimension | v1 | Deferred |
| --- | --- | --- |
| Side | **Server** (host an agent) | Client (call agents) |
| Protocol | **v1.0 only** | v0.3 backward-compat |
| Transports | **JSON-RPC + REST** | gRPC |
| Types | **hand-written structs** | proto-generated wire layer (with gRPC) |
| Concurrency | **PubSub + process-per-task** | — |
| HTTP | **plug-first, mountable**; Bandit standalone optional | — |
| Persistence | **ETS default** behind a behaviour | first-party Ecto adapter |

ADRs: [0001](decisions/0001-server-first-scope.md),
[0002](decisions/0002-target-v1.0-only.md),
[0003](decisions/0003-jsonrpc-and-rest-transports.md),
[0004](decisions/0004-hand-written-types.md),
[0005](decisions/0005-pubsub-process-model.md),
[0006](decisions/0006-plug-first-mounting.md),
[0007](decisions/0007-ets-task-store.md),
[0008](decisions/0008-v1-feature-tiers.md).

## Feature tiers (ADR-0008)

### Must-have — a spec-compliant, genuinely useful agent

- `AgentExecutor` behaviour + `TaskUpdater` ergonomic helper.
- JSON-RPC + REST request handler: `message/send` (+ streaming SSE),
  `tasks/get`, `tasks/list`, `tasks/cancel`, `tasks/resubscribe`.
- Agent card served at `/.well-known/agent-card.json`.
- `TaskState` lifecycle + event model over PubSub.
- `:telemetry` events for observability.

### Should-have — strong value, moderate cost (included in v1)

- **Push notifications** — webhook sender + config store. The other half of
  long-running-task delivery for clients that can't hold a stream open; both
  reference SDKs treat it as core.
- **Extensions negotiation** — `A2A-Extensions` header → activated extensions.
- **Server-side auth/user model** — `A2A.User` + `user_resolver` hook.

### Deferred — designed around, added later

- **gRPC transport** — needs a proto toolchain and a separate server stack for
  the least-used binding. Handler boundary is gRPC-ready.
  ([ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md))
- **v0.3 compatibility layer** — a large parallel type set + bidirectional
  translators; roughly doubles the type surface. The ecosystem is moving to 1.0.
  ([ADR-0002](decisions/0002-target-v1.0-only.md))
- **Agent card signing** (JWS + JCS) — real crypto + canonicalization; only
  needed by clients verifying card authenticity.
  ([ADR-0008](decisions/0008-v1-feature-tiers.md))
- **First-party Ecto adapter** — a fast-follow package once the `TaskStore`
  behaviour is proven. ([ADR-0007](decisions/0007-ets-task-store.md))
- **The client side** — a separate effort after the server story lands.
  ([ADR-0001](decisions/0001-server-first-scope.md))

## Why these boundaries

The unifying principle: **prove the OTP-native core against a real, streaming,
cancellable, resumable, webhook-delivering agent before broadening.** Every
deferred item is either (a) additive behind an existing behaviour/boundary
(Ecto, gRPC, client) or (b) a self-contained optional module (v0.3 compat,
signing) — so nothing deferred forces a later breaking change to the core.

## Interop validation (cross-cutting workstream)

Because we hand-write types rather than share a generator with the reference
SDKs, v1 must prove wire compatibility:

- Capture request/response and event corpora from the Python and JS SDKs.
- Golden round-trip tests in `A2A.JSON` ([Data model](data-model.md)).
- End-to-end: drive our server with the reference SDKs' clients (or captured
  request corpora) as the interop oracle.

## Roadmap sketch (post-v1, unordered)

1. First-party Ecto/Postgres `TaskStore` adapter.
2. Client side (`ClientFactory`, transports, card resolver, interceptors).
3. Agent card signing + verification.
4. gRPC transport (server, then client).
5. v0.3 compatibility layer as an optional package.

## Related

- [Architecture overview](../architecture.md)
- [Decision records](decisions/README.md)
