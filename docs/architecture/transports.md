# Transports

[← Architecture](../architecture.md)

## Decision in brief

Ship **two transports** — JSON-RPC and HTTP+JSON/REST — behind **one
transport-agnostic `RequestHandler`**. The wire layer is a **Plug** that mounts
into any Plug or Phoenix pipeline; a thin `A2A.Standalone` boots Bandit for
users with no web framework. gRPC is deferred but the handler boundary is
designed so it can be added as a third adapter without touching agent code.

Rationale: [ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md) (transports)
and [ADR-0006](decisions/0006-plug-first-mounting.md) (plug-first mounting).

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

## `A2A.Plug.Router`

A `Plug.Router` mountable anywhere:

```elixir
# In a Phoenix/Plug app — mount under a path:
forward "/a2a", to: A2A.Plug.Router, init_opts: [handler: MyAgent.Handler]

# Standalone — no web framework:
A2A.Standalone.start_link(handler: MyAgent.Handler, port: 4000)
```

Routes exposed:

| Method & path | Purpose | Doc |
| --- | --- | --- |
| `GET /.well-known/agent-card.json` | Serve the `AgentCard` | [Data model](data-model.md) |
| `POST /` | JSON-RPC endpoint (all methods, incl. SSE streaming) | below |
| REST resource routes (`/v1/…`) | HTTP+JSON binding | below |

### Dependencies

- **Hard:** `plug` (mounting into any pipeline needs only this).
- **Optional:** `bandit` — only for `A2A.Standalone`. Mounting into an existing
  Phoenix/Plug app needs no server dependency from us.

This subpath/optional-dependency isolation mirrors the reference SDKs' deliberate
split that keeps server deps out of the graph for consumers who don't need them.

## JSON-RPC binding

- Single `POST /` endpoint; dispatch by JSON-RPC `method` name to the
  corresponding `RequestHandler` callback.
- Requests/responses use the JSON-RPC 2.0 envelope; errors render via
  `A2A.Error.to_jsonrpc/1` (code + message + data). See
  [Cross-cutting concerns](cross-cutting.md#errors).
- Streaming methods (`message/stream`, `tasks/resubscribe`) respond as
  **Server-Sent Events**.

## REST (HTTP+JSON) binding

- Resource-style routes; proto3-JSON request/response bodies via `A2A.JSON`.
- Content type `application/a2a+json`.
- Errors render via `A2A.Error.to_rest/1` (HTTP status + body).
- The same streaming methods use SSE, identically to JSON-RPC.

## SSE streaming (`A2A.Plug.SSE`)

Streaming is where the OTP model pays off. The SSE handler:

1. Subscribes to the task's PubSub topic (see [Process model](process-model.md)).
2. **Peeks the first event before flushing SSE headers** — a technique taken
   directly from the reference SDKs so that an *early* error surfaces as a proper
   JSON-RPC/HTTP error envelope rather than a `200` SSE stream that then fails.
3. Streams subsequent events with `Plug.Conn.chunk/2`, formatting each as an SSE
   `data:` frame carrying the JSON-encoded `StreamResponse`.
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
