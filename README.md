# a2a_sdk_ex

An Elixir SDK for building [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/v1.0.0/specification/)
servers — agentic applications that expose their capabilities over A2A, built on
OTP for first-class streaming, cancellation, resumption, and webhook delivery.

A peer of the official [Python](https://github.com/a2aproject/a2a-python) and
[JavaScript](https://github.com/a2aproject/a2a-js) SDKs — same protocol, same
architectural seams — but designed for the Elixir/OTP ecosystem rather than
ported line-by-line.

> **Status:** the typed foundation, the server-core runtime — blocking
> `message/send`, streaming `message/stream` and `tasks/resubscribe` (shared
> `EventStream`, configurable drain timeout) over the OTP process model — and
> the JSON-RPC HTTP transport (`A2A.Plug.Router`/`A2A.Plug.SSE`, optional
> `A2A.Standalone`) are implemented, with a runnable
> [`examples/echo_server/`](examples/echo_server); REST, cancel, `tasks/list`,
> and push are the next phases. Design under [`docs/`](docs/architecture.md).

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

## Requirements

- **Elixir 1.18+**
- **Erlang/OTP 26+**

The library is tested in CI across Elixir 1.18 / 1.19 / 1.20, each against the
lowest OTP it supports at or above the OTP 26 floor.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
