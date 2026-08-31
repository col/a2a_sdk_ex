# Transports

[← Architecture](../architecture.md)

## Decision in brief

Ship **two transports** — JSON-RPC and HTTP+JSON/REST — behind **one
transport-agnostic `RequestHandler`**. The wire layer is a **Plug** that mounts
into any Plug or Phoenix pipeline; a thin `A2A.Standalone` boots Bandit for
users with no web framework. gRPC is deferred but the handler boundary is
designed so it can be added as a third adapter without touching agent code.

**Status:** both bindings have **landed** — `A2A.Plug.Router` (mountable
`Plug.Router`), `A2A.Plug.JSONRPC` (envelope decode/dispatch), `A2A.Plug.REST`
(REST transport mechanics), `A2A.Plug.SSE` (streaming, reused by both
bindings), the agent-card route, and optional `A2A.Standalone` (Bandit).
JSON-RPC serves `message/send`, `message/stream`, `tasks/get`,
`tasks/cancel`, `tasks/list`, `tasks/resubscribe`, and the four
push-notification-config methods; REST serves the same operations over
resource-style routes. `/{tenant}/…` scoping remains deferred (see
[ADR-0011](decisions/0011-rest-binding-and-cancel-list.md)).

Rationale: [ADR-0003](decisions/0003-jsonrpc-and-rest-transports.md) (transports),
[ADR-0006](decisions/0006-plug-first-mounting.md) (plug-first mounting),
[ADR-0010](decisions/0010-jsonrpc-transport-first.md) (JSON-RPC ships first;
REST follows), [ADR-0011](decisions/0011-rest-binding-and-cancel-list.md)
(REST binding + `cancel`/`list` land), and
[ADR-0012](decisions/0012-push-notifications.md) (push notification config +
delivery land).

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
| `POST /` | JSON-RPC endpoint (`message/send`, `message/stream`, `tasks/get`, `tasks/cancel`, `tasks/list`, `tasks/resubscribe`; streaming methods respond as SSE) | below |
| `POST /message:send` | REST: `message/send` (`application/a2a+json`) | below |
| `POST /message:stream` | REST: `message/stream` (SSE) | below |
| `GET /tasks/:id` | REST: `tasks/get` (`application/a2a+json`) | below |
| `GET /tasks` | REST: `tasks/list` (`application/a2a+json`) | below |
| `POST /tasks/:id:cancel` | REST: `tasks/cancel` (`application/a2a+json`) | below |
| `GET /tasks/:id:subscribe` | REST: `tasks/resubscribe` (SSE) | below |
| `POST /tasks/:task_id/pushNotificationConfigs` | REST: `tasks/pushNotificationConfig/set` (`application/a2a+json`) | below |
| `GET /tasks/:task_id/pushNotificationConfigs` | REST: `tasks/pushNotificationConfig/list` (`application/a2a+json`) | below |
| `GET /tasks/:task_id/pushNotificationConfigs/:id` | REST: `tasks/pushNotificationConfig/get` (`application/a2a+json`) | below |
| `DELETE /tasks/:task_id/pushNotificationConfigs/:id` | REST: `tasks/pushNotificationConfig/delete` (`application/a2a+json`) | below |

Routes follow the vendored proto's `google.api.http` annotations exactly — no
invented `/v1` prefix.

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
- Ten methods are wired: `message/send`, `message/stream` (unary vs. stream),
  `tasks/get`, `tasks/cancel`, `tasks/list`, `tasks/resubscribe`, and
  `tasks/pushNotificationConfig/{set,get,list,delete}`. An unknown method
  renders `-32601`.
- Requests/responses use the JSON-RPC 2.0 envelope; envelope-level errors
  (parse error `-32700`, invalid request `-32600`, method not found `-32601`,
  invalid params `-32602`) and semantic errors render via
  `A2A.Error.to_jsonrpc/1` (code + message + data). See
  [Cross-cutting concerns](cross-cutting.md#errors).
- Streaming methods (`message/stream`, `tasks/resubscribe`) respond as
  **Server-Sent Events** via `A2A.Plug.SSE`.

## REST (HTTP+JSON) binding — **landed**

Landed per [ADR-0011](decisions/0011-rest-binding-and-cancel-list.md) —
`A2A.Plug.REST` is the transport-mechanics twin of `A2A.Plug.JSONRPC`: build a
typed request from path params + query + body via `A2A.JSON`, call
`A2A.Server.DefaultHandler`, and tag the result for `A2A.Plug.Router` to
render.

- Resource-style routes (see the table above), proto3-JSON request/response
  bodies via `A2A.JSON`. Routes follow the vendored proto's
  `google.api.http` annotations exactly — no invented `/v1` prefix.
- Success responses use content type `application/a2a+json`.
- Errors render via `A2A.Error.to_rest/1` — `{http_status, body}` where `body`
  is `google.rpc.Status` ProtoJSON (a `code` int, `message`, and a `details`
  array with one `google.rpc.ErrorInfo`). See
  [Cross-cutting concerns](cross-cutting.md#errors) for the full status table.
- Streaming routes (`message:stream`, `tasks/:id:subscribe`) use the same
  `A2A.Plug.SSE` core as JSON-RPC, via `SSE.respond/4`'s frame-formatter
  argument — REST passes a formatter that emits the bare `StreamResponse`
  ProtoJSON with no JSON-RPC envelope.
- One wire nuance: Plug's router treats a mid-segment `:` as a dynamic-param
  marker, so the proto's literal `:send`/`:stream` suffixes are written
  escaped in the router (`post "/message\:send"`), and `:cancel`/`:subscribe`
  are recovered by matching the `:id` segment and stripping the known suffix.
- Push-notification-config routes (`/tasks/{task_id}/pushNotificationConfigs…`,
  landed per [ADR-0012](decisions/0012-push-notifications.md)) return
  `push_notification_not_supported` (→ `400`) when the server wasn't started
  with `push_notifications: true`.
- **Deferred:** `/{tenant}/…` additional bindings (scoping is still a
  single `A2A.Scope`; non-tenant routes only for now).

## SSE streaming (`A2A.Plug.SSE`) — **landed**

Streaming is where the OTP model pays off. The SSE handler:

1. Subscribes to the task's PubSub topic (see [Process model](process-model.md)).
2. **Peeks the first event before flushing SSE headers** — a technique taken
   directly from the reference SDKs so that an *early* error surfaces as a proper
   JSON-RPC/HTTP error envelope rather than a `200` SSE stream that then fails.
3. Streams subsequent events with `Plug.Conn.chunk/2`, formatting each as an SSE
   `data:` frame via a pluggable formatter (`SSE.respond/4`). JSON-RPC's
   formatter (the default, `A2A.Plug.JSONRPC.stream_frame/2`) wraps each frame
   in a **full JSON-RPC response envelope**
   (`{"jsonrpc": "2.0", "id": ..., "result": ...}`) carrying one
   `StreamResponse` as `result`; REST's formatter (`A2A.Plug.REST.frame/2`)
   emits the bare `StreamResponse` ProtoJSON with no envelope. The
   subscribe/peek/chunk mechanics are shared — only the frame formatter
   differs.
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
  [ADR-0006](decisions/0006-plug-first-mounting.md),
  [ADR-0010](decisions/0010-jsonrpc-transport-first.md),
  [ADR-0011](decisions/0011-rest-binding-and-cancel-list.md),
  [ADR-0012](decisions/0012-push-notifications.md).
