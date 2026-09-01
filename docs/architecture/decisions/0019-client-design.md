# 19. Client design: facade + transport behaviour, injectable HTTP, header-passthrough auth

Date: 2026-09-01
Status: Accepted

## Context

`a2a_sdk_ex` shipped a spec-compliant **server** (JSON-RPC + REST transports,
streaming, push, identity/ownership, authenticated extended card) but no way
to **call** an A2A agent from Elixir. A two-sided protocol needs both sides,
and the typed foundation (`A2A.Types.*`, `A2A.JSON`, the `A2A.Error` code
table) already models every request/response shape and round-trips the wire
form — a client is largely wiring: build a typed request, put it on the wire
for a chosen binding, and parse the typed response (or invert a wire error
back into `%A2A.Error{}`).

A survey of prior art (Python `a2a-python`'s `Client`/`ClientTransport`/
`ClientFactory`, JS/TS `a2a-js`'s `Client`/`Transport`/`pickMatchingInterface`,
and the Elixir `a2a_ex` hex package, which shares our exact `A2A.Types.*` /
`A2A.Error` namespace) converges on one shape: a facade in front of a
transport strategy, card-driven transport selection, and streaming exposed as
a lazy enumerable. The full design is recorded in
[`docs/superpowers/specs/2026-09-01-a2a-client-design.md`](../../superpowers/specs/2026-09-01-a2a-client-design.md);
this ADR captures the decisions that are hard to reverse.

## Decision

**Mirror the server's shape on the caller side: one transport-neutral facade
in front of N wire bindings, with HTTP itself behind an injectable seam.**

- **`A2A.Client`** is a plain value (`%A2A.Client{agent_card, transport,
  endpoint, config}`), not a process — no supervision, no serialization
  point; the underlying HTTP client owns its own connection pool. It is built
  once by `connect/2` and is immutable thereafter.
- **`A2A.Client.Transport`** is a behaviour with one callback per operation;
  `A2A.Client.Transport.JSONRPC` and `A2A.Client.Transport.REST` are the two
  implementations, each building the wire form via `A2A.JSON`, calling the
  HTTP layer, and decoding the response (or wire error) back to typed structs
  / `%A2A.Error{}`. A `gRPC` adapter can join later behind the same
  behaviour with no facade change.
- **`A2A.Client.HTTP`** is the sole HTTP-client seam: a behaviour with
  `request/1` (unary) and `stream/2` (SSE). `A2A.Client.HTTP.Req` is the
  shipped adapter, gated on the already-optional `:req` dependency; a test or
  a host with different requirements injects any module implementing the
  behaviour. Timeouts, retries, tracing, and auth-refresh are composed at
  this seam by the caller (e.g. `Req.Steps`) — never inside the client core.
- **Discovery is decoupled from connection.** `fetch_agent_card/2` fetches +
  decodes the base `AgentCard` and nothing else; `connect/2` accepts either a
  URL (fetch, then select) or an already-held `%AgentCard{}` (select only, no
  network). `connect(url)` is exactly `fetch_agent_card(url)` composed with
  `connect(card)` — one-call ergonomics stay, and the two steps are
  independently usable (fetch once, connect many times; supply a card
  obtained out-of-band).
- **Transport selection is card-based**, via
  `A2A.Client.Transport.Selector`, porting the reference SDKs' algorithm
  (Python `_find_best_interface`, JS `pickMatchingInterface`): build a
  priority list from `config.preferred_transports` followed by the card's
  `supported_interfaces` in card order (de-duplicated, case-insensitive on
  binding name); prefer `protocol_version == "1.0"` when a binding appears at
  multiple versions; walk the list and pick the first binding both advertised
  and implemented. Default is **server preference** (card order wins); a
  caller opts into client preference by setting `preferred_transports`. No
  overlap is `{:error, %A2A.Error{code: :unsupported_operation}}`.
- **Streaming is a lazy enumerable that raises mid-stream.**
  `send_message_stream/3` and `resubscribe/3` return `{:ok, Enumerable.t()}`
  built with `Stream.resource/3` over the HTTP adapter's SSE stream, yielding
  decoded `StreamResponse` arms (`Task`, `TaskStatusUpdateEvent`,
  `TaskArtifactUpdateEvent`, `Message`). It must be **enumerated once, in the
  calling process** (mirroring the server-side `EventStream` gotcha); halting
  the enumeration **cancels the underlying HTTP request**; a mid-stream
  protocol error (a `StreamResponse` frame carrying an error, on either
  binding) is **raised** as `%A2A.Error{}` rather than yielded as an
  `{:error, _}` element, so a plain `for`-comprehension over events stays
  idiomatic. `Config.stream_timeout` defaults to **`120_000` ms** — generous
  relative to a typical unary HTTP timeout, matching agent turns that
  routinely wait on LLM latency (the same reasoning behind `a2a_elixir_sdk`'s
  120s streaming default) — and bounds the gap between events, not the
  stream's total lifetime.
- **Auth is header passthrough.** Per ADR-0018 the server resolves the caller
  from the request via its own `user_resolver`; the client's job is only to
  send credentials as headers (`Authorization: Bearer …`, etc.), supplied
  per-call in `opts[:headers]` or as `Config` defaults, forwarded verbatim
  through `A2A.Client.HTTP`. No client-side credential service, token
  refresh, or 401-retry — a caller needing those composes them into a custom
  `A2A.Client.HTTP` adapter (e.g. a `Req` step).
- **The authenticated extended card** is reachable via
  `get_extended_agent_card/2` — the same request machinery with auth headers
  set; against a server without an `extended_agent_card_resolver` it decodes
  the `:extended_agent_card_not_configured` error like any other wire error.
- **Errors are inverted through one decoder**, `A2A.Client.Error`: JSON-RPC
  integer codes map back to `A2A.Error` atoms via the reverse of the §5.4
  table (lifting `google.rpc.ErrorInfo.metadata` from the `data` array); REST
  parses the AIP-193 body, preferring `ErrorInfo.reason` over the HTTP status;
  transport faults (connection refused, DNS, TLS, timeout) map to
  `%A2A.Error{code: :timeout | :internal_error}` with the underlying reason
  preserved in `data`. Both bindings converge on the same struct — the
  client-side complement to the server's "one table, two projections."

### Deferred

Recorded here so a later effort has a fixed starting point rather than an
open question:

- **Interceptor / middleware chain** — HTTP-level cross-cutting concerns are
  served today by the injectable `A2A.Client.HTTP` seam; no protocol-level
  onion chain is built or stubbed.
- **Client-side credential service, token refresh, 401-retry** — auth stays
  header-passthrough; a host composes these into its own `HTTP` adapter.
- **gRPC transport** — the `Transport` behaviour leaves room; no adapter yet.
- **Client-side polling loop** — `return_immediately`/`polling` is passed
  through to the server; the client does not loop `get_task` itself.
- **v0.3 legacy compatibility** — 1.0-only, matching the server
  ([ADR-0002](0002-target-v1.0-only.md)).
- **Agent-card signature verification** — no JWS/JCS verification of a
  fetched card, same deferred class as server-side card signing
  ([ADR-0008](0008-v1-feature-tiers.md)).

## Consequences

- The client and server share one architectural shape (transport-neutral
  core behind N wire bindings), so a reader who understands one half already
  recognizes the other's seams.
- `A2A.Client.HTTP` is the only place a socket is ever opened; the rest of
  the client (facade, both transports, the selector, the error decoder) is
  unit-testable with a stub and no toolchain, matching the server's
  ETS-behind-a-behaviour testability story.
- `req` stays optional: a host without it (or with different infrastructure
  requirements) supplies its own `A2A.Client.HTTP` implementation and loses
  nothing but the default adapter. Absent both `req` and an injected
  `:http_client`, unary and streaming calls raise a clear configuration
  error rather than a cryptic one.
- Enumerate-once-and-halt-cancels is now a contract the SDK asks of every
  caller of a streaming function, on both the server (`EventStream`
  consumers) and the client (`send_message_stream/3`/`resubscribe/3`
  consumers) — one mental model, documented at both call sites.
- Raising on a mid-stream protocol error means a caller who wants
  `{:ok, _} | {:error, _}` uniformity around streaming must wrap enumeration
  in `try`/`rescue` themselves; this was a deliberate trade favoring a clean
  `for`-comprehension over a uniform return shape (recorded as the rejected
  alternative in the design spec).
- Nothing here blocks the deferred items from landing later: gRPC is another
  `Transport` implementation, an interceptor chain would wrap
  `A2A.Client.HTTP` rather than replace it, and credential refresh is
  additive at the same seam — no core rework anticipated.
