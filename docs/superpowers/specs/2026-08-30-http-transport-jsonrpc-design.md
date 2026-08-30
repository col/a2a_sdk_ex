# HTTP transport — Phase 1: JSON-RPC over Plug

Status: approved (brainstorm 2026-08-30)
Branch: `throng/AA-12`

## Purpose

The server runtime now streams, resumes, and stores tasks — but only through the
in-process `A2A.Server.RequestHandler` API. Nothing listens on a socket. This
phase puts the **first HTTP transport** in front of that handler: a mountable
`Plug.Router` speaking A2A's primary **JSON-RPC** binding, an optional Bandit
standalone boot, and a served agent card — enough for a real, `curl`-able
**end-to-end** agent. It ships with an `examples/echo_server/` project that
proves the whole path.

Per [ADR-0003](../../architecture/decisions/0003-jsonrpc-and-rest-transports.md)
the wire layer is transport-agnostic over one handler; per
[ADR-0006](../../architecture/decisions/0006-plug-first-mounting.md) it is a
`Plug.Router` mountable into any Plug/Phoenix pipeline. This phase realises both
for JSON-RPC. REST (`/v1/…`) is the following transport phase, sequenced by the
new [ADR-0010](../../architecture/decisions/0010-jsonrpc-transport-first.md).

No new protocol semantics are introduced — the transport only parses the wire
form into the existing typed requests, calls the existing handler, and renders
the typed result (or `A2A.Error`) back. The four operations the runtime already
serves are exposed; `tasks/cancel` and `tasks/list` stay unimplemented.

## Scope

### In

- **`A2A.Plug.Router`** — a `Plug.Router`, initialised with a `:server` name, that
  serves the agent card, accepts the JSON-RPC `POST /`, and dispatches by method.
- **`A2A.Plug.JSONRPC`** — envelope decode/encode and method → handler mapping;
  pure, transport-mechanics only (no `Plug.Conn`).
- **`A2A.Plug.SSE`** — the streaming response: subscribe/obtain the frame
  enumerable in the request process, **peek the first frame before headers**,
  then chunk `StreamResponse` frames as SSE `data:` events.
- **`A2A.Standalone`** — a Bandit-backed `start_link/1` booting the router on a
  port for zero-framework use (optional `bandit` dependency).
- **`A2A.Error.to_jsonrpc/1`** — semantic error atom → JSON-RPC error object.
- **`A2A.Server` handle + `Supervisor`** gain an optional **`:agent_card`**
  (`%A2A.Types.AgentCard{}`), stored on the handle and served at the card route.
- **`examples/echo_server/`** — a standalone Mix project (path dep on `:a2a`)
  wiring an `EchoExecutor`, an agent card, and `A2A.Standalone`, with a README of
  `curl` recipes.
- **Dependencies:** `{:plug, "~> 1.16"}` (hard runtime); `{:bandit, "~> 1.5",
  optional: true}` (+ dev/test visibility for the standalone smoke test).

### Out (deferred, additive behind these seams)

- **REST / `/v1` binding** and `application/a2a+json` — next transport phase;
  reuses this router, dispatch, SSE, and error rendering. `A2A.Error.to_rest/1`
  lands with it.
- **`tasks/cancel`, `tasks/list`** — need runtime work (execution-process
  signalling; store listing). Until then the router returns JSON-RPC
  method-not-found for them.
- **Push notifications, extensions negotiation, `user_resolver`/real auth,
  telemetry events, agent-card signing, gRPC** — later phases, each behind a seam
  this phase leaves untouched.

## Architecture

### One handler, one transport (this phase)

```
  JSON-RPC POST / ─▶ A2A.Plug.Router ─▶ A2A.Plug.JSONRPC ─▶ RequestHandler ─▶ execution
                            │                                 (DefaultHandler)
  GET /.well-known ─────────┘  (card, no handler)
  streaming methods ───────▶ A2A.Plug.SSE ─▶ StreamResponse enumerable (this handler)
```

The router owns HTTP concerns (routing, status, headers, chunking); `JSONRPC`
owns the envelope and method map; the handler owns protocol semantics. Nothing
protocol-semantic lives in the transport.

### `A2A.Plug.Router`

A `Plug.Router` (`plug :match` / `plug :dispatch`), initialised at mount with
`init_opts: [server: <name>]`. It resolves the handle via `A2A.Server.handle/1`
per request (cheap `:persistent_term` read), so the router holds no state beyond
the server name.

| Route | Behaviour |
| --- | --- |
| `GET /.well-known/agent-card.json` | if `handle.agent_card` set → `200`, `application/json`, `A2A.JSON.encode!(card)`; else `404` |
| `POST /` | read body, hand to `A2A.Plug.JSONRPC`; non-streaming → `200` JSON envelope; streaming → delegate to `A2A.Plug.SSE` |
| _other_ | `404` |

Mounting:

```elixir
# In a Phoenix/Plug pipeline:
forward "/a2a", to: A2A.Plug.Router, init_opts: [server: MyAgent]

# Standalone:
A2A.Standalone.start_link(server: MyAgent, port: 4000)
```

### `A2A.Plug.JSONRPC` — envelope & dispatch

JSON-RPC 2.0. A request object is `%{"jsonrpc" => "2.0", "method" => m, "params"
=> p, "id" => id}`. Decode/validate the envelope, then map `method` to a handler
call, decoding `params` into the typed request via `A2A.JSON.from_json_map/2`:

| `method` | `params` decodes to | Handler call | Result shape |
| --- | --- | --- | --- |
| `message/send` | `SendMessageRequest` | `send_message/3` | `SendMessageResponse` (`task`/`message`) |
| `message/stream` | `SendMessageRequest` | `send_message_stream/2` | **SSE** of `StreamResponse` |
| `tasks/get` | `GetTaskRequest` | `get_task/2` | `Task` |
| `tasks/resubscribe` | `SubscribeToTaskRequest` | `resubscribe/2` | **SSE** of `StreamResponse` |

Return values are tagged for the router to render:

- non-streaming ok → `{:reply, result_struct}` → JSON-RPC `result` (encoded via
  `A2A.JSON.to_json_map/1`, wrapped in the response envelope with the request
  `id`).
- non-streaming error → `{:error, %A2A.Error{}}` → `A2A.Error.to_jsonrpc/1`.
- streaming → `{:stream, enumerable}` → router hands to `A2A.Plug.SSE`.

Envelope-level failures render as JSON-RPC errors without touching the handler:

| Condition | Code |
| --- | --- |
| body is not valid JSON | `-32700` parse error |
| not a conforming request object (missing `jsonrpc`/`method`) | `-32600` invalid request |
| `method` not in the table above | `-32601` method not found |
| `params` fail to decode into the request struct | `-32602` invalid params |

Batch requests are **out of scope** (A2A does not use them); a JSON array body is
an invalid request (`-32600`).

### `A2A.Plug.SSE`

The payoff of the OTP model — a client holds one connection and receives frames
as the task produces them. The handler-returned enumerable is the streaming
source (`send_message_stream/2` / `resubscribe/2`), already governed by the
"enumerate once, in the calling process" contract and `EventStream`'s
three-signal termination.

Sequence (in the request process, so PubSub events land in the right mailbox):

1. Obtain the enumerable (the handler already subscribed eagerly in this
   process). For `resubscribe/2`, a `{:error, not_found}` here renders as a
   normal JSON-RPC error — **no SSE started**.
2. **Peek the first frame** (`Enum.take/2`-style, one element) *before* sending
   headers. This mirrors the reference SDKs: an early error surfaces as a proper
   JSON-RPC/HTTP error envelope, not a `200` stream that immediately fails.
3. Send `200`, `content-type: text/event-stream`, `cache-control: no-cache`, and
   `Plug.Conn.send_chunked/2`.
4. Emit the peeked frame, then stream the rest: each `StreamResponse` →
   `A2A.JSON.encode!/1` → `Plug.Conn.chunk(conn, "data: " <> json <> "\n\n")`.
5. End when the enumerable halts (terminal frame / execution `:DOWN` / — for
   streaming — never an idle timeout). A client disconnect (`chunk/2` returns
   `{:error, _}`) stops iteration; the enumerable's after-fun unsubscribes, and
   because execution is independent of the consumer the task keeps running and is
   re-attachable via `tasks/resubscribe`.

No async-generator cleanup dance is needed — unsubscribe on halt is all a
disconnect requires (ADR-0006).

### `A2A.Standalone`

A thin `start_link/1` that boots **Bandit** serving `A2A.Plug.Router` with the
given `:server` and `:port` (default 4000). It is a supervised child users can
drop into their own tree. Bandit is an **optional** dependency — mounting into an
existing Phoenix/Plug app needs none of it; only standalone mode pulls it in.
`A2A.Standalone` raises a clear error if `bandit` is not loaded.

### `A2A.Error.to_jsonrpc/1`

Maps the semantic error set ([cross-cutting](../../architecture/cross-cutting.md#errors))
to a JSON-RPC error object `%{"code" => integer, "message" => string, "data" =>
term}`, using A2A's assigned codes where defined and standard JSON-RPC codes
otherwise:

| Error atom | JSON-RPC code |
| --- | --- |
| `:task_not_found` | `-32001` |
| `:task_not_continuable` / `:task_in_progress` (not cancelable / already active) | `-32002` |
| `:unsupported_operation` | `-32004` |
| `:content_type_not_supported` | `-32005` |
| `:invalid_agent_response` | `-32006` |
| `:timeout` / `:internal_error` / unmapped | `-32603` internal error |

Envelope-level codes (`-32700/-32600/-32601/-32602`) are produced directly by
`A2A.Plug.JSONRPC`, not by `to_jsonrpc/1` (they precede any handler call). `data`
carries the existing `A2A.Error.data` map (e.g. `%{task_id: …}`) when present.

### Server handle: `:agent_card`

`A2A.Server.Supervisor.start_link/1` gains an optional `:agent_card`
(`%A2A.Types.AgentCard{}`), stored on the `A2A.Server` struct (new field,
default `nil`) alongside `executor`, `store`, etc. It is the only runtime change
this phase makes — the card route reads it; when unset, the route `404`s. No
generation or signing: the host supplies a fully-formed struct.

## The echo example (`examples/echo_server/`)

A self-contained Mix project — a copy-pasteable template and the phase's
end-to-end proof.

```
examples/echo_server/
  mix.exs                       {:a2a, path: "../.."}, {:bandit, "~> 1.5"}
  lib/echo_server/
    application.ex              supervises A2A.Server.Supervisor + A2A.Standalone
    executor.ex                 EchoExecutor (@behaviour A2A.Server.AgentExecutor)
    agent_card.ex               builds the advertised %AgentCard{}
  README.md                     curl recipes
```

- `EchoExecutor.execute/2` mirrors the tested `A2A.Test.EchoExecutor`:
  `start_work |> add_artifact("echo: " <> RequestContext.user_input(ctx)) |>
  complete("done")`. It implements `cancel/2` as a no-op-ish reject.
- `application.ex` starts a `Phoenix.PubSub`, the `A2A.Server.Supervisor` (with
  the executor and card), and `A2A.Standalone` on port 4000.
- `agent_card.ex` advertises a single `AgentInterface` (JSON-RPC binding, the
  server URL) and one echo skill, with `capabilities.streaming: true`.
- README `curl` recipes: fetch the card; `message/send` returning the echoed
  task; `curl -N` against `message/stream` showing SSE frames.

The example is **not** part of the umbrella build or `mix test`; it is run
manually (`cd examples/echo_server && mix deps.get && mix run --no-halt`). Its
existence and shape are asserted only indirectly (the standalone smoke test in
the main suite covers the same wiring).

## Error handling summary

- **Transport/envelope** — malformed JSON, non-request bodies, unknown methods,
  undecodable params → JSON-RPC `-327xx` without a handler call.
- **Semantic** — handler `{:error, %A2A.Error{}}` → `to_jsonrpc/1`. `tasks/get`
  on an unknown id → `-32001`; continuing a terminal task → `-32002`.
- **Streaming early error** — `resubscribe/2` on an unknown task renders a
  JSON-RPC error *before* any SSE headers (peek-first).
- **Mid-stream abnormal end** — enumerable halts on execution `:DOWN`; the SSE
  simply ends after the last frame (transports do not synthesise an error frame,
  consistent with the Phase-2 streaming contract). Clients learn terminal state
  via the last frame or a subsequent `tasks/get`.
- **Client disconnect** — `chunk/2` error stops iteration; unsubscribe on halt;
  task keeps running.

## Testing strategy (TDD)

Everyday `mix test` stays green with no proto toolchain. New tests under
`test/a2a/plug/` and `test/a2a/`.

- **`A2A.Plug.JSONRPC` unit:** envelope decode/validate; method → call mapping;
  the four `-327xx` envelope errors; result/stream/error tagging. No socket.
- **`A2A.Error.to_jsonrpc/1` unit:** the full code table above; `data`
  pass-through; unmapped atom → `-32603`.
- **Router integration (`Plug.Test`):** conns through `A2A.Plug.Router` against a
  real supervised server + `EchoExecutor`:
  - `GET /.well-known/agent-card.json` → card JSON (round-trips through
    `A2A.JSON`); `404` when no card configured.
  - `message/send` happy path → echoed task in the JSON-RPC `result`.
  - `tasks/get` for that task → the stored task; unknown id → `-32001`.
  - envelope errors: bad JSON (`-32700`), non-request (`-32600`), unknown method
    e.g. `tasks/cancel` (`-32601`), bad params (`-32602`).
- **SSE (`A2A.Plug.SSE`):** drive `message/stream`; assert ordered `data:` frames
  parse back to the expected `StreamResponse` sequence and end on terminal; the
  peek-first early-error path (reuse `Replay`/`Gated`/`Boom` executors); a
  `resubscribe` unknown-task renders a JSON-RPC error, not a 200 stream.
- **Standalone smoke:** boot `A2A.Standalone` on an ephemeral port (`port: 0` /
  OS-assigned), real HTTP round-trip for the card and a `message/send`. Runs in
  `mix test` because `bandit` is dev/test-visible. Uses the setup server (single
  global ETS table constraint — see CLAUDE.md).

## Documentation & housekeeping

- **New ADR** [0010](../../architecture/decisions/0010-jsonrpc-transport-first.md):
  JSON-RPC-first sequencing. Added to the ADR README table.
- Update `docs/architecture/transports.md`: mark JSON-RPC + card + standalone as
  landed; REST still pending. Reconcile the route table with what ships.
- Update `docs/architecture/cross-cutting.md#errors`: `to_jsonrpc/1` now exists;
  note the code table.
- Update `CLAUDE.md`: server-runtime paragraph (HTTP transport landed; `plug`
  hard dep, `bandit` optional; new `examples/` dir and its run instructions) and
  the dependency-graph line (`jason` + `phoenix_pubsub` + `plug`).
- Update `README.md` status line.
- `mix.exs`: add `plug`, optional `bandit`; keep the runtime graph documented.
- `.formatter.exs` / `mix format` must continue to exclude the generated proto
  subtree; the new `examples/` project has its own `mix.exs` and is not part of
  the root build.

## Related

- [Phase 2 streaming design](2026-08-30-server-core-phase2-streaming-design.md)
  (produces the `StreamResponse` enumerable this phase encodes)
- [Transports](../../architecture/transports.md)
- [Cross-cutting concerns](../../architecture/cross-cutting.md)
- ADRs [0003](../../architecture/decisions/0003-jsonrpc-and-rest-transports.md),
  [0006](../../architecture/decisions/0006-plug-first-mounting.md),
  [0009](../../architecture/decisions/0009-eventstream-termination.md),
  [0010](../../architecture/decisions/0010-jsonrpc-transport-first.md)
