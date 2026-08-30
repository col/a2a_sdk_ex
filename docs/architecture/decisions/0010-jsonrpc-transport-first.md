# 10. JSON-RPC transport first; REST follows

Date: 2026-08-30
Status: Accepted

## Context

[ADR-0003](0003-jsonrpc-and-rest-transports.md) commits v1 to two HTTP+JSON
bindings — **JSON-RPC** and **REST** — behind one transport-agnostic
`A2A.Server.RequestHandler`. [ADR-0006](0006-plug-first-mounting.md) fixes the
wire layer as a mountable `Plug.Router` plus an optional Bandit-backed
standalone boot. Neither ADR settled *sequencing*: whether the first transport
phase ships both bindings at once or one then the other.

Two facts push toward splitting the work:

- The server runtime today implements only four handler operations —
  `send_message/3`, `get_task/2`, `send_message_stream/2`, `resubscribe/2`.
  `cancel_task/2` and `list_tasks/2` are declared on the behaviour but
  unimplemented. Neither binding can expose more than the runtime serves.
- JSON-RPC is A2A's primary/default binding and carries the full method set
  including SSE streaming; both reference SDKs lead with it. REST is a second
  resource-style projection of the *same* handler calls — additive, not
  foundational.

Shipping both bindings in one phase roughly doubles the routing/rendering
surface and the test matrix for no gain in what an agent can actually do, and
delays the first end-to-end HTTP scenario.

## Decision

The first transport phase ships **JSON-RPC only**, mounted as `A2A.Plug.Router`
with an optional `A2A.Standalone` (Bandit) boot. It exposes the four methods the
runtime serves (`message/send`, `message/stream` over SSE, `tasks/get`,
`tasks/resubscribe`) plus the `GET /.well-known/agent-card.json` card route.
REST (`/v1/…`, `application/a2a+json`) is a **following phase** that reuses the
same router, handler dispatch, SSE mechanics, and error rendering.

This does not revise ADR-0003 (both bindings remain the v1 target) — it records
that they land in sequence, JSON-RPC first.

## Consequences

- The first end-to-end HTTP scenario (the echo example, `curl`-able) arrives a
  phase sooner, over the binding clients most expect.
- The one-handler/N-transports boundary is exercised by a real transport before
  a second one is added, so REST slots in behind a proven seam rather than being
  co-designed speculatively.
- `A2A.Error` gains `to_jsonrpc/1` this phase; `to_rest/1` waits for the REST
  phase. The semantic error set ([cross-cutting](../cross-cutting.md#errors)) is
  transport-neutral, so the second renderer is additive.
- `tasks/cancel` and `tasks/list` remain absent from the wire until the runtime
  implements them; the router returns a JSON-RPC method-not-found for the
  unmounted methods, an honest reflection of current capability.
- The SSE implementation (`A2A.Plug.SSE`) is written once here and reused
  verbatim by REST, matching ADR-0003's "SSE implemented once" consequence.
