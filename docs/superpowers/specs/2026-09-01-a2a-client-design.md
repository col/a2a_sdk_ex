# A2A Client — design

Date: 2026-09-01
Status: Proposed
Branch: `throng/AA-21`

## Summary

Add `A2A.Client` — the caller-side counterpart to the `A2A.Server.*` runtime.
It resolves an agent's `AgentCard`, selects a transport the agent advertises,
and exposes the full A2A v1.0 operation set over **both** the JSON-RPC and REST
bindings, reusing the existing `A2A.Types.*` structs, the `A2A.JSON` codec, and
the `A2A.Error` code table (inverted, wire → struct).

The client is a **plain value** (`%A2A.Client{}`), not a process. HTTP is behind
an **injectable behaviour** (`A2A.Client.HTTP`) with a first-party `Req` adapter,
so the whole client is unit-testable without a socket and driven end-to-end
against our own server for interop.

This is the first client-side effort; scope is the "solid core" tier — all
operations, both transports, streaming, card-based transport selection, and the
authenticated extended card — while deliberately deferring middleware, gRPC,
client-side polling loops, and v0.3 compatibility (see [Out of scope](#out-of-scope)).

## Motivation

`a2a_sdk_ex` ships a spec-compliant **server** (JSON-RPC + REST transports,
streaming, push, identity/ownership, authenticated extended card) but no way to
**call** an A2A agent from Elixir. An SDK for a two-sided protocol needs both
sides. The typed foundation already models every request/response shape and the
codec round-trips them, so a client is largely wiring: build a typed request,
put it on the wire for the chosen binding, parse the typed response (or decode a
wire error back into `%A2A.Error{}`).

### Prior art surveyed

- **Python** (`a2aproject/a2a-python`, `src/a2a/client`): `Client` facade over a
  `ClientTransport` (JSON-RPC / REST / gRPC), built by a `ClientFactory` that
  selects transport from the card; `A2ACardResolver`; interceptor chain + auth
  interceptor; everything surfaced as an async iterator.
- **JS/TS** (`a2aproject/a2a-js`, `src/client`): `Client` facade over a
  `Transport` interface, `ClientFactory` + `pickMatchingInterface` for selection;
  async generators for streaming; auth as a `fetch`-wrapper with 401-retry;
  `CallInterceptor` onion chain.
- **Elixir `a2a_ex`** (lukaszsamson, hex `a2a_ex`): closest analog — shares our
  exact `A2A.Types.*` / `A2A.Error` namespace. `A2A.Client` with polymorphic
  target (URL or `AgentCard`), Req-backed lazy-enumerable streams whose halt
  cancels the request, `select_interface`/`transport_for_binding` helpers,
  per-call `opts` for auth. **No** interceptor chain.

The convergent shape (facade + transport strategy + card-driven selection +
streaming-as-lazy-enumerable) is what this design adopts, idiomatised to Elixir:
tagged tuples over exceptions, a plain struct over an actor, an injectable HTTP
behaviour over a mutation-based interceptor chain.

## Architecture

### One facade, N transports (mirror of the server)

The server put one transport-neutral `RequestHandler` behind N wire bindings.
The client is the dual: one `A2A.Client` facade **in front of** N transports.

```
                    ┌─ A2A.Client.Transport.JSONRPC ─┐
 A2A.Client  ──▶    ├─ A2A.Client.Transport.REST  ───┤ ──▶  A2A.Client.HTTP  ──▶ agent
 (facade,           └─ [future] gRPC ────────────────┘      (behaviour;            (server)
  a struct)              (behaviour)                          Req adapter)
```

- **`A2A.Client`** — public facade. Holds resolved card, selected transport +
  endpoint, and config. Every function funnels through one private
  `dispatch/4` that calls the selected transport module.
- **`A2A.Client.Transport`** — behaviour: one callback per operation. Two
  implementations, JSON-RPC and REST. Each builds the wire form via `A2A.JSON`,
  calls the HTTP layer, and decodes the response (or wire error) back to typed
  structs / `%A2A.Error{}`.
- **`A2A.Client.HTTP`** — behaviour: `request/1` (unary) and `stream/2` (SSE).
  `A2A.Client.HTTP.Req` is the shipped adapter (optional `:req` dep). Tests
  inject a stub. This is the sole HTTP-client seam — timeouts, retries, tracing,
  auth-refresh are all composed here by the user (e.g. `Req.Steps`), never in the
  client core.

### Module layout

| Module | Purpose |
| --- | --- |
| `A2A.Client` | Facade: `connect/2` + operations; `%A2A.Client{}` struct |
| `A2A.Client.Config` | `%Config{}`: `preferred_transports`, `streaming?`, default `headers`/`opts`, `http_client` (module), `http_opts` |
| `A2A.Client.CardResolver` | Fetch + decode `AgentCard` from `/.well-known/agent-card.json` |
| `A2A.Client.Transport` | Behaviour — the wire operations |
| `A2A.Client.Transport.JSONRPC` | JSON-RPC 2.0 envelope build/parse, method dispatch, SSE frame decode |
| `A2A.Client.Transport.REST` | REST path/query/body build, `application/json` + AIP-193 decode, SSE frame decode |
| `A2A.Client.Transport.Selector` | Card interfaces × preference → `{transport_module, url}` |
| `A2A.Client.HTTP` | Behaviour — `request/1`, `stream/2` (injectable) |
| `A2A.Client.HTTP.Req` | First-party Req adapter (optional dep) |
| `A2A.Client.Error` | Decode wire errors → `%A2A.Error{}` (inverse of the §5.4 table) |

### The `%A2A.Client{}` struct

```elixir
%A2A.Client{
  agent_card: %A2A.Types.AgentCard{},        # resolved at connect
  transport:  A2A.Client.Transport.JSONRPC,  # selected module
  endpoint:   "https://host/a2a",            # selected interface URL
  config:     %A2A.Client.Config{}
}
```

Built once by `connect/2`; immutable data thereafter. No supervision, no
serialization point — the underlying HTTP client owns its own connection pool.

## Public API

All operations return `{:ok, term()} | {:error, A2A.Error.t()}` unless noted.
Each takes a final optional `opts` keyword (per-call `headers`, `http_opts`,
`timeout`, `history_length`, etc.), merged over `Config` defaults.

```elixir
# Construction / discovery
fetch_agent_card(url, opts \\ [])         :: {:ok, AgentCard.t()} | {:error, A2A.Error.t()}
connect(url_or_card, opts \\ [])          :: {:ok, t()} | {:error, A2A.Error.t()}
agent_card(client)                        :: AgentCard.t()          # already-resolved base card
get_extended_agent_card(client, opts \\ []) :: {:ok, AgentCard.t()} | {:error, A2A.Error.t()}

# Core operations
send_message(client, message, opts \\ [])        :: {:ok, Task.t() | Message.t()} | {:error, A2A.Error.t()}
send_message_stream(client, message, opts \\ [])  :: {:ok, Enumerable.t()} | {:error, A2A.Error.t()}
get_task(client, task_id, opts \\ [])            :: {:ok, Task.t()} | {:error, A2A.Error.t()}
cancel_task(client, task_id, opts \\ [])         :: {:ok, Task.t()} | {:error, A2A.Error.t()}
list_tasks(client, opts \\ [])                   :: {:ok, ListTasksResponse.t()} | {:error, A2A.Error.t()}
resubscribe(client, task_id, opts \\ [])         :: {:ok, Enumerable.t()} | {:error, A2A.Error.t()}

# Push-notification config CRUD
create_push_config(client, config, opts \\ [])   :: {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
get_push_config(client, task_id, config_id, opts \\ []) :: {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
list_push_configs(client, task_id, opts \\ [])   :: {:ok, ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
delete_push_config(client, task_id, config_id, opts \\ []) :: :ok | {:error, A2A.Error.t()}
```

### Discovery is decoupled from connection

Fetching a card, building a client, and doing both are three separate concerns.
The three entry points compose rather than nest behaviour:

- **`fetch_agent_card(url, opts)`** — fetch + decode the base card from
  `/.well-known/agent-card.json` and return `{:ok, %AgentCard{}}`. No transport
  selection, no client built. A thin public wrapper over
  `A2A.Client.CardResolver.resolve/2` for callers who just want to inspect a
  card (capabilities, security schemes, advertised interfaces) or cache it.
- **`connect(%AgentCard{}, opts)`** — build a `%A2A.Client{}` from a card the
  caller **already holds**: run transport selection only, **no network fetch**.
  Lets a caller fetch once and connect many times, supply a card obtained
  out-of-band, or pin a hand-built card.
- **`connect(url, opts)`** — the convenience path, **unchanged**: `fetch_agent_card/2`
  then `connect(card, opts)`. Equivalent to
  `with {:ok, card} <- fetch_agent_card(url, opts), do: connect(card, opts)`.

So `connect(url)` is exactly `fetch_agent_card` + `connect(card)` — the existing
one-call ergonomics stay, and the two steps are independently usable.

### Message input

`send_message/3` and `send_message_stream/3` accept a ready
`%A2A.Types.Message{}` **or** a `%A2A.Types.SendMessageRequest{}` (when the
caller wants to set `configuration`/`metadata`). A bare `Message` is wrapped into
a `SendMessageRequest` with `Config`-derived defaults. No sugar/builder helpers
in this cut (a later `A2A.Client.Message.text/1`-style helper is additive).

## Behaviour: streaming

`send_message_stream/3` and `resubscribe/3` return `{:ok, Enumerable.t()}` once
the request is established. The enumerable is **lazy** — built with
`Stream.resource/3` over the HTTP adapter's SSE stream — and yields decoded
`%A2A.Types.*` **event structs** (`Task`, `TaskStatusUpdateEvent`,
`TaskArtifactUpdateEvent`, `Message`), i.e. the arms of `StreamResponse`.

Contract, mirroring the server's SSE decisions:

- **Enumerate once, in the calling process.** The stream owns an HTTP connection;
  enumerating it elsewhere or not at all leaks the connection until GC. Documented
  on both functions (same wording as the server-side gotcha).
- **Halting cancels the request.** Breaking out of the enumeration closes the
  underlying HTTP stream (the Req adapter's `into:`/cancel path), matching
  `a2a_ex` and the JS `.return()` semantics.
- **Mid-stream protocol errors raise.** A `StreamResponse` frame carrying an error
  (JSON-RPC per-event `error`, or a REST error body) is raised as `%A2A.Error{}`
  during enumeration, so a `for`-comprehension over events stays clean. (Decided
  in brainstorming; the alternative — an `{:error, _}` element — was rejected.)
- **Termination** follows the server: the stream ends on a task-terminal event or
  a single direct `Message`. The client does not impose its own idle timeout
  beyond the HTTP adapter's `receive_timeout`.

## Behaviour: transport selection

`A2A.Client.Transport.Selector` ports the reference algorithm (Python
`_find_best_interface`, JS `pickMatchingInterface`) for cross-SDK consistency:

1. Read the card's `supported_interfaces` (each `%AgentInterface{url,
   protocol_binding, protocol_version}`).
2. Build a priority list: `config.preferred_transports ++ (interface bindings in
   card order)`, de-duplicated, case-insensitive on binding name.
3. Prefer `protocol_version == "1.0"` when the same binding appears at multiple
   versions.
4. Walk the priority list; pick the first binding that (a) the card advertises
   and (b) we implement (`JSONRPC` | `REST`). Its `url` becomes `endpoint`.
5. No overlap → `{:error, %A2A.Error{code: :unsupported_operation, ...}}`.

Default is **server preference** (card order wins); a caller opts into client
preference by setting `config.preferred_transports`. Binding-name mapping matches
what the server advertises for JSON-RPC and REST (HTTP+JSON).

`connect/2` accepts either a URL (→ `fetch_agent_card/2` via `CardResolver`, then
select) or a pre-fetched `%AgentCard{}` (→ select directly, no network). See
[Discovery is decoupled from connection](#discovery-is-decoupled-from-connection).
A caller may also pin a transport explicitly via `opts` to bypass selection.

## Behaviour: errors

`A2A.Client.Error` is the inverse of `A2A.Error.to_jsonrpc/1` / `to_rest/1`:

- **JSON-RPC:** map the integer `code` back to the `A2A.Error` atom via a reverse
  of the `@errors` table; carry `message`; when `data` is the §9.5
  `[google.rpc.ErrorInfo]` array, lift its `metadata` into `A2A.Error.data`.
  Unknown codes → `:internal_error` (or `:unsupported_operation` where the code is
  A2A-reserved but unmapped), preserving the raw code/message.
- **REST:** parse the AIP-193 body (`error.{code,status,message,details}`); prefer
  the `ErrorInfo.reason` in `details` to recover the exact atom, falling back to
  the HTTP status. Carry `message` and `metadata`.
- **Transport faults** (connection refused, DNS, TLS, timeout) → `%A2A.Error{code:
  :timeout | :internal_error, ...}` with the underlying reason in `data`.

Because both bindings decode into the same `%A2A.Error{}`, callers get identical
error handling regardless of transport — the symmetric complement to the server's
"one table, two projections."

## Wire contract (reference)

The client speaks exactly what the server serves.

**JSON-RPC** — single `POST /` (endpoint URL), PascalCase methods (spec §5.3):
`SendMessage`, `SendStreamingMessage`, `GetTask`, `SubscribeToTask`, `CancelTask`,
`ListTasks`, `CreateTaskPushNotificationConfig`, `GetTaskPushNotificationConfig`,
`ListTaskPushNotificationConfigs`, `DeleteTaskPushNotificationConfig`,
`GetExtendedAgentCard`. Streaming methods respond as SSE.

**REST** — resource routes (spec §11, proto `google.api.http`):

| Op | Method & path |
| --- | --- |
| SendMessage | `POST /message:send` |
| SendStreamingMessage | `POST /message:stream` (SSE) |
| GetTask | `GET /tasks/{id}?historyLength=` |
| CancelTask | `POST /tasks/{id}:cancel` |
| ListTasks | `GET /tasks?contextId=…` |
| SubscribeToTask | `POST /tasks/{id}:subscribe` (SSE) — server also accepts `GET`; client uses `POST` per §11.3.2 |
| GetExtendedAgentCard | `GET /extendedAgentCard` |
| Create/List push config | `POST` / `GET /tasks/{task_id}/pushNotificationConfigs` |
| Get/Delete push config | `GET` / `DELETE /tasks/{task_id}/pushNotificationConfigs/{id}` |

**Base card:** `GET /.well-known/agent-card.json` (both bindings share it).

## Authentication

Per ADR-0018, the server resolves the caller from the `Plug.Conn` via
`user_resolver` (the host verifies credentials in its own plug pipeline) and
owner-scopes its stores. The client's responsibility is therefore only to **send
credentials as headers** — e.g. `Authorization: Bearer …` — supplied per-call in
`opts[:headers]` or as `Config` defaults, passed straight through the HTTP
adapter. `get_extended_agent_card/2` is the same request with auth headers set;
against a server without an `extended_agent_card_resolver` it decodes the
`:extended_agent_card_not_configured` error like any other.

No client-side credential-service, token refresh, or 401-retry in this cut; a
user needing those composes them into a custom `A2A.Client.HTTP` adapter (e.g. a
Req step).

## Dependencies

- **Hard:** `jason` (already). The client core (facade, transports, selector,
  error decode) uses only the existing typed foundation + `jason`.
- **Optional:** `req` — needed only for the default `A2A.Client.HTTP.Req` adapter
  and for SSE consumption. Absent Req, unary and streaming both raise a clear
  "add `:req` or supply a `:http_client`" error; a user may inject any adapter
  (Finch/Tesla/Mint/test stub) implementing `A2A.Client.HTTP`.

No new hard dependencies. `plug`/`bandit`/`phoenix_pubsub` remain server-only.

## Testing

- **Unit (no sockets):** every transport, the selector, the card resolver, and
  the error decoder against a **stubbed `A2A.Client.HTTP`** returning canned wire
  payloads (reuse `test/support/fixtures.ex`). Covers request encoding, response
  decoding, both error projections, transport selection ranking, and streaming
  frame decode / mid-stream raise / halt-cancels.
- **Integration (interop oracle):** drive the real client over **both** bindings
  against our own server started via `A2A.Standalone`, configured with a
  `user_resolver` + `extended_agent_card_resolver` so auth and the extended card
  have a live SUT. Exercises: connect+discover, send (blocking), stream (multi
  event to terminal), get/cancel/list, push CRUD, extended card (authorised and
  `not_configured`), and transport selection against a dual-interface card.
- A small dedicated fixture agent (likely a new `examples/client_server`, or a
  reuse of `echo_server` extended with an extended-card resolver) provides a
  predictable SUT; the reuse-vs-new call is made in the implementation plan.

TDD throughout; everyday `mix test` stays green with no extra toolchain (client
tests need no `protoc`; integration tests need `req` + `bandit`, already
available in dev/test).

## Out of scope

Deferred, designed around, recorded in the accompanying ADR:

- **Interceptor / middleware chain** — HTTP-level cross-cutting (retry, tracing,
  auth-refresh, default headers) is served by the injectable `A2A.Client.HTTP`
  adapter today; a protocol-level chain is not built and not stubbed.
- **Client-side credential service / token refresh / 401-retry** — auth is
  header passthrough.
- **gRPC transport** — the `Transport` behaviour leaves room; no adapter now.
- **Client-side polling loop** — `return_immediately`/`polling` is passed to the
  server; the client does not loop `get_task` itself.
- **v0.3 legacy compatibility** — 1.0-only, matching the server.
- **Agent-card signature verification** — no JWS/JCS verification of fetched
  cards.

## Deliverables

1. `A2A.Client.*` modules per the layout above.
2. `A2A.Client.HTTP` behaviour + `A2A.Client.HTTP.Req` adapter.
3. Unit + integration test suites; fixture SUT (new/reused example agent).
4. **ADR-0019** — "Client design: facade + transport behaviour, injectable HTTP,
   header-passthrough auth; middleware/gRPC/polling deferred."
5. Doc updates: `docs/architecture/transports.md` (client selection section),
   `docs/architecture/scope-and-roadmap.md` (client moves from deferred to
   in-progress), `CLAUDE.md` (client paragraph + any new gotchas), `mix.exs`
   docs grouping.

## Open questions

None blocking. The reuse-vs-new example-server decision and the exact
`A2A.Client.HTTP` callback signatures are settled during the implementation plan.
