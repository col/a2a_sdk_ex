# Transports

[← Architecture](../architecture.md)

## Decision in brief

Ship **two transports** — JSON-RPC and HTTP+JSON/REST — behind **one
transport-agnostic `RequestHandler`**. The wire layer is a **Plug** that mounts
into any Plug or Phoenix pipeline; a thin `A2A.Standalone` boots Bandit for
users with no web framework. gRPC is deferred but the handler boundary is
designed so it can be added as a third adapter without touching agent code.

**Status:** the JSON-RPC binding has **landed** — `A2A.Plug.Router` (mountable
`Plug.Router`), `A2A.Plug.JSONRPC` (envelope decode/dispatch), `A2A.Plug.SSE`
(streaming), the agent-card route, and optional `A2A.Standalone` (Bandit). The
four wired methods are `message/send`, `message/stream`, `tasks/get`, and
`tasks/resubscribe` — `tasks/cancel`, `tasks/list`, and the REST/HTTP+JSON
binding are still pending (see [ADR-0010](decisions/0010-jsonrpc-transport-first.md)).

Rationale: [ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md) (transports),
[ADR-0006](decisions/0006-plug-first-mounting.md) (plug-first mounting), and
[ADR-0010](decisions/0010-jsonrpc-transport-first.md) (JSON-RPC ships first;
REST follows).

## One handler, N transports

Both reference SDKs converged on this shape (JS: `jsonRpcHandler` + `restHandler`
+ `grpcService` over one `DefaultRequestHandler`; Python: JSON-RPC/REST/gRPC
dispatchers over one `RequestHandler`). We keep it:

```
   JSON-RPC POST ─┐
                  ├─▶ A2A.Server.RequestHandler (DefaultHandler) ─▶ execution
   REST routes ───┘        (protocol logic, transport-neutral)

   [future] gRPC ─────────▲  drops in here, same handler
```

The transport layer's only jobs are: parse the wire form into a typed request,
call the handler, render the typed result (or `A2A.Error`) back to the wire.
Nothing protocol-semantic lives in a transport.

## `A2A.Plug.Router` — **landed**

A `Plug.Router` mountable anywhere:

```elixir
# In a Phoenix/Plug app — mount under a path:
forward "/a2a", to: A2A.Plug.Router, init_opts: [handler: MyAgent.Handler]

# Standalone — no web framework:
A2A.Standalone.start_link(handler: MyAgent.Handler, port: 4000)
```

Routes exposed today:

| Method & path | Purpose | Doc |
| --- | --- | --- |
| `GET /.well-known/agent-card.json` | Serve the `AgentCard` | [Data model](data-model.md) |
| `POST /` | JSON-RPC endpoint (`message/send`, `message/stream`, `tasks/get`, `tasks/resubscribe`; streaming methods respond as SSE) | below |

REST resource routes (`/v1/…`) are **not yet implemented** — see below.

### Dependencies

- **Hard:** `plug` (mounting into any pipeline needs only this).
- **Optional:** `bandit` — only for `A2A.Standalone`. Mounting into an existing
  Phoenix/Plug app needs no server dependency from us.

This subpath/optional-dependency isolation mirrors the reference SDKs' deliberate
split that keeps server deps out of the graph for consumers who don't need them.

## JSON-RPC binding — **landed**

- Single `POST /` endpoint (`A2A.Plug.Router`); `A2A.Plug.JSONRPC` decodes the
  envelope, dispatches by JSON-RPC `method` name to the corresponding
  `A2A.Server.DefaultHandler` callback, and re-encodes the result.
- Four methods are wired: `message/send`, `message/stream` (unary vs. stream),
  `tasks/get`, `tasks/resubscribe`. `tasks/cancel` and `tasks/list` are
  declared on the `RequestHandler` behaviour but not yet dispatched here — an
  unknown method renders `-32601`.
- Requests/responses use the JSON-RPC 2.0 envelope; envelope-level errors
  (parse error `-32700`, invalid request `-32600`, method not found `-32601`,
  invalid params `-32602`) and semantic errors render via
  `A2A.Error.to_jsonrpc/1` (code + message + data). See
  [Cross-cutting concerns](cross-cutting.md#errors).
- Streaming methods (`message/stream`, `tasks/resubscribe`) respond as
  **Server-Sent Events** via `A2A.Plug.SSE`.

## REST (HTTP+JSON) binding — **pending**

Deferred to a follow-on phase per [ADR-0010](decisions/0010-jsonrpc-transport-first.md);
not yet implemented. The intended shape:

- Resource-style routes; proto3-JSON request/response bodies via `A2A.JSON`.
- Content type `application/a2a+json`.
- Errors render via `A2A.Error.to_rest/1` (HTTP status + body) — `to_rest/1`
  does not exist yet.
- The same streaming methods would use SSE, identically to JSON-RPC.

## SSE streaming (`A2A.Plug.SSE`) — **landed**

Streaming is where the OTP model pays off. The SSE handler:

1. Subscribes to the task's PubSub topic (see [Process model](process-model.md)).
2. **Peeks the first event before flushing SSE headers** — a technique taken
   directly from the reference SDKs so that an *early* error surfaces as a proper
   JSON-RPC/HTTP error envelope rather than a `200` SSE stream that then fails.
3. Streams subsequent events with `Plug.Conn.chunk/2`, formatting each as an SSE
   `data:` frame. Each frame is a **full JSON-RPC response envelope**
   (`{"jsonrpc": "2.0", "id": ..., "result": ...}`) carrying one `StreamResponse`
   as `result` — not a bare `StreamResponse` — built by
   `A2A.Plug.JSONRPC.stream_frame/2`.
4. Ends when a terminal (or `input_required`) event arrives. A client
   disconnect simply unsubscribes; because the execution process is independent
   of the consumer, the task keeps running and can be re-attached via
   `resubscribe`.

No async-generator `.return()`/`finally` dance is needed (the source of much
complexity in the JS SDK) — unsubscribing is all that a disconnect requires.

## Transport selection & the agent card

The `AgentCard` advertises which transports the server supports via
`supported_interfaces` (each an `AgentInterface` with `url` +
`protocol_binding` + `protocol_version`). A single `DefaultHandler` can be
exposed over both bindings simultaneously; the card lists both so clients pick
one. (Client-side transport *selection* is out of v1 scope — see
[Scope and roadmap](scope-and-roadmap.md).)

## Adding gRPC later

gRPC is deferred (needs a proto toolchain + a separate server stack for the
least-used binding — [ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md)).
When added it becomes a third adapter calling the same `RequestHandler`, with a
generated protobuf-binary wire layer sitting behind the public
[data-model](data-model.md) structs. No agent code changes.

## Related

- [Request handling](request-handling.md) — the handler these transports call.
- [Streaming and events](streaming-and-events.md) — what flows over SSE.
- [ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md),
  [ADR-0006](decisions/0006-plug-first-mounting.md).
