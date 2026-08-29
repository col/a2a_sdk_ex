# 8. v1 feature tiers

Date: 2026-08-29
Status: Accepted

## Context

Beyond the core request/execute/stream/store loop, the reference SDKs carry
several cross-cutting features: push notifications, extensions negotiation,
server-side auth/user model, agent card signing, telemetry. Including everything
delays a first release; including too little makes it a toy. We need an explicit
tiering for a v1 that is both shippable and genuinely useful.

## Decision

Tier v1 features as follows:

**Must-have** — `AgentExecutor` + `TaskUpdater`; JSON-RPC + REST handler with
`message/send` (+ SSE), `tasks/get`, `tasks/list`, `tasks/cancel`,
`tasks/resubscribe`; agent card serving; `TaskState` lifecycle + event model;
`:telemetry` events.

**Should-have (included in v1)** — push notifications (webhook sender + config
store); extensions negotiation (`A2A-Extensions`); server-side auth/user model
(`A2A.User` + resolver hook).

**Deferred** — agent card signing (JWS/JCS); gRPC transport; v0.3 compat; Ecto
adapter; the client side.

## Consequences

- v1 is an agent that streams, cancels, resumes, delivers webhooks, negotiates
  extensions, and knows its caller — a credible first release, not a demo.
- Push notifications are protected as the highest-value "should", since
  long-running-task delivery to clients that can't hold a stream open is a
  headline A2A capability.
- Agent card signing is the notable cut from "must": it needs real crypto + RFC-
  8785 canonicalization and is only needed by clients *verifying* card
  authenticity, not by an agent hosting itself.
- Telemetry uses `:telemetry` (emit events; users attach handlers) rather than
  baking in OpenTelemetry, keeping the core dependency-free while supporting
  production observability. Details in [Cross-cutting concerns](../cross-cutting.md).
