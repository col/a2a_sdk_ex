# 6. Plug-first, mountable HTTP layer

Date: 2026-08-29
Status: Accepted

## Context

Both reference SDKs deliberately ship the HTTP layer as **mountable middleware**,
not a monolithic server (JS: Express handlers you `app.use`; Python: Starlette
`Route`s you attach). This lets an agent slot into an application that already
has a web server — a common case, and specifically the Phoenix-embedding case we
want to support well.

In Elixir the natural unit of composable HTTP handling is a **Plug**. A plain
Plug router mounts into any Plug or Phoenix pipeline; Bandit can serve it
standalone for users with no web framework.

## Decision

The HTTP layer is a **`Plug.Router`** (`A2A.Plug.Router`) that mounts anywhere
via `forward`, plus an optional `A2A.Standalone` that boots Bandit for zero-
framework use. `plug` is the only hard web dependency; `bandit` is optional and
needed only for standalone mode.

## Consequences

- Agents embed cleanly into existing Phoenix/Plug apps (`forward "/a2a", to:
  A2A.Plug.Router`), reusing the host's endpoint, TLS, and auth pipeline.
- Standalone users get a one-line boot without us forcing a server dependency on
  everyone.
- The plug delegates all protocol semantics to the transport-agnostic
  `RequestHandler` ([ADR-0003](0003-jsonrpc-and-rest-transports.md)); it only
  parses/renders the wire form.
- SSE is implemented with `Plug.Conn.chunk/2` over a PubSub subscription
  ([ADR-0005](0005-pubsub-process-model.md)), avoiding the async-generator
  cleanup complexity of the reference SDKs (see [Transports](../transports.md)).
