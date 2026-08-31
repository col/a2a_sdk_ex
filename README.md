# a2a_sdk_ex

An Elixir SDK for building [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/v1.0.0/specification/)
servers — agentic applications that expose their capabilities over A2A, built on
OTP for first-class streaming, cancellation, resumption, and webhook delivery.

A peer of the official [Python](https://github.com/a2aproject/a2a-python) and
[JavaScript](https://github.com/a2aproject/a2a-js) SDKs — same protocol, same
architectural seams — but designed for the Elixir/OTP ecosystem rather than
ported line-by-line.

> **Status:** the typed foundation, the server-core runtime — blocking
> `message/send`, streaming `message/stream` and `tasks/resubscribe`, plus
> `tasks/cancel` and `tasks/list` (shared `EventStream`, configurable drain
> timeout) over the OTP process model — and both HTTP transports, JSON-RPC and
> REST (`A2A.Plug.Router`/`A2A.Plug.JSONRPC`/`A2A.Plug.REST`/`A2A.Plug.SSE`,
> optional `A2A.Standalone`), are implemented, with a runnable
> [`examples/echo_server/`](examples/echo_server); push notifications and
> multi-tenant scoping are the next phases. Design under
> [`docs/`](docs/architecture.md).

## Try it

Both HTTP bindings are mounted by [`examples/echo_server/`](examples/echo_server)
(`mix run --no-halt` from that directory, port 5001). JSON-RPC:

```bash
curl -s http://localhost:5001/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "message/send",
    "params": {"message": {"messageId": "m1", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}}
  }' | jq
```

REST — same call, resource-style, `application/a2a+json`:

```bash
curl -s http://localhost:5001/message:send \
  -H 'content-type: application/json' \
  -d '{"message": {"messageId": "m1", "role": "ROLE_USER",
    "parts": [{"text": "hello"}]}}' | jq
```

List and cancel tasks over REST:

```bash
curl -s http://localhost:5001/tasks | jq
curl -s -X POST http://localhost:5001/tasks/<task-id>:cancel | jq
```

See the example's own [README](examples/echo_server/README.md) for the full
walkthrough (agent card, streaming over both bindings).

## Design decisions

The scope and shape of v1 are captured as Architecture Decision Records. In
short:

| Decision | Choice | ADR |
| --- | --- | --- |
| Scope | Server-side only (host an agent); client deferred | [0001](docs/architecture/decisions/0001-server-first-scope.md) |
| Protocol | A2A v1.0 only; no v0.3 compat | [0002](docs/architecture/decisions/0002-target-v1.0-only.md) |
| Transports | JSON-RPC + REST behind one handler; gRPC deferred | [0003](docs/architecture/decisions/0003-jsonrpc-and-rest-transports.md) |
| Types | Hand-written idiomatic structs + a proto3-JSON codec | [0004](docs/architecture/decisions/0004-hand-written-types.md) |
| Concurrency | Process-per-task + `Phoenix.PubSub` fan-out | [0005](docs/architecture/decisions/0005-pubsub-process-model.md) |
| HTTP | Plug-first, mountable; Bandit standalone optional | [0006](docs/architecture/decisions/0006-plug-first-mounting.md) |
| Persistence | `TaskStore` behaviour + ETS default; Ecto fast-follow | [0007](docs/architecture/decisions/0007-ets-task-store.md) |
| v1 features | Streaming, cancel, resubscribe, push, extensions, auth | [0008](docs/architecture/decisions/0008-v1-feature-tiers.md) |

Full context and consequences for each: [decision records](docs/architecture/decisions/README.md).

## Documentation

- **[Architecture overview](docs/architecture.md)** — the high-level map: components, boundaries, invariants.
- Detailed docs under [`docs/architecture/`](docs/architecture/): data model, process model, request handling, transports, streaming & events, persistence, cross-cutting concerns, scope & roadmap.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
