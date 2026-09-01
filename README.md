# a2a_sdk_ex

[![Hex.pm](https://img.shields.io/hexpm/v/a2a_sdk.svg)](https://hex.pm/packages/a2a_sdk)
[![Docs](https://img.shields.io/badge/hexdocs-docs-8e7ce6.svg)](https://hexdocs.pm/a2a_sdk)

An Elixir SDK for building [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/v1.0.0/specification/)
servers — agentic applications that expose their capabilities over A2A, built on
OTP for first-class streaming, cancellation, resumption, and webhook delivery.

A peer of the official [Python](https://github.com/a2aproject/a2a-python) and
[JavaScript](https://github.com/a2aproject/a2a-js) SDKs — same protocol, same
architectural seams — but designed for the Elixir/OTP ecosystem rather than
ported line-by-line.

> **Status:** the typed foundation, the server-core runtime — blocking
> `SendMessage`, streaming `SendStreamingMessage` and `SubscribeToTask`, plus
> `CancelTask` and `ListTasks` (shared `EventStream`, configurable drain
> timeout) over the OTP process model — and both HTTP transports, JSON-RPC and
> REST (`A2A.Plug.Router` with internal JSONRPC/REST/SSE plugs,
> optional `A2A.Standalone`), plus opt-in **push notifications** (config CRUD
> on both bindings + best-effort webhook delivery, `push_notifications: true`),
> are implemented, with a runnable
> [`examples/echo_server/`](https://github.com/col/a2a_sdk_ex/tree/main/examples/echo_server);
> multi-tenant scoping is the next phase. Design under
> [`docs/`](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture.md).

## Installation

Add `:a2a_sdk` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:a2a_sdk, "~> 0.1.0"}
  ]
end
```

## Try it

Both HTTP bindings are mounted by [`examples/echo_server/`](https://github.com/col/a2a_sdk_ex/tree/main/examples/echo_server)
(`mix run --no-halt` from that directory, port 5001). JSON-RPC:

```bash
curl -s http://localhost:5001/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "SendMessage",
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

See the example's own [README](https://github.com/col/a2a_sdk_ex/blob/main/examples/echo_server/README.md) for the full
walkthrough (agent card, streaming over both bindings).

### Push notifications

Enable delivery with `push_notifications: true` on `A2A.Server.Supervisor`,
then register a webhook for a task (also settable inline via
`SendMessageConfiguration.task_push_notification_config` on `SendMessage`):

```bash
curl -s -X POST http://localhost:5001/tasks/<task-id>/pushNotificationConfigs \
  -H 'content-type: application/json' \
  -d '{"url": "https://my-service.example/webhooks/a2a", "token": "shared-secret"}' | jq
```

Each subsequent task event is POSTed to the webhook as a `StreamResponse`
(`application/a2a+json`), same shape as an SSE frame. A host that enables push
must also set `AgentCard.capabilities.push_notifications = true` to advertise
support — see [ADR-0012](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0012-push-notifications.md).

## Design decisions

The scope and shape of v1 are captured as Architecture Decision Records. In
short:

| Decision | Choice | ADR |
| --- | --- | --- |
| Scope | Server-side only (host an agent); client deferred | [0001](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0001-server-first-scope.md) |
| Protocol | A2A v1.0 only; no v0.3 compat | [0002](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0002-target-v1.0-only.md) |
| Transports | JSON-RPC + REST behind one handler; gRPC deferred | [0003](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0003-jsonrpc-and-rest-transports.md) |
| Types | Hand-written idiomatic structs + a proto3-JSON codec | [0004](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0004-hand-written-types.md) |
| Concurrency | Process-per-task + `Phoenix.PubSub` fan-out | [0005](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0005-pubsub-process-model.md) |
| HTTP | Plug-first, mountable; Bandit standalone optional | [0006](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0006-plug-first-mounting.md) |
| Persistence | `TaskStore` behaviour + ETS default; Ecto fast-follow | [0007](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0007-ets-task-store.md) |
| v1 features | Streaming, cancel, resubscribe, push, extensions, auth | [0008](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture/decisions/0008-v1-feature-tiers.md) |

Full context and consequences for each: [decision records](https://github.com/col/a2a_sdk_ex/tree/main/docs/architecture/decisions).

## Documentation

- **[Architecture overview](https://github.com/col/a2a_sdk_ex/blob/main/docs/architecture.md)** — the high-level map: components, boundaries, invariants.
- Detailed docs under [`docs/architecture/`](https://github.com/col/a2a_sdk_ex/tree/main/docs/architecture): data model, process model, request handling, transports, streaming & events, persistence, cross-cutting concerns, scope & roadmap.

## Requirements

- **Elixir 1.18+**
- **Erlang/OTP 26+**

The library is tested in CI across Elixir 1.18 / 1.19 / 1.20, each against the
lowest OTP it supports at or above the OTP 26 floor.

## License

Licensed under the [Apache License, Version 2.0](https://github.com/col/a2a_sdk_ex/blob/main/LICENSE).

## Releasing

Releases publish automatically when a `vX.Y.Z` tag is pushed (`.github/workflows/release.yml`),
gated on the full CI suite.

**One-time setup:** enable 2FA on your hex.pm account, generate a write key
(`mix hex.user key generate --permission api:write --key-name a2a-sdk-ci`), and
add it as the `HEX_API_KEY` secret under repo Settings → Secrets → Actions.

**Each release:**
1. Update `CHANGELOG.md` (move `Unreleased` → the new version) and bump `@version` in `mix.exs`.
2. Merge to `main` and confirm CI is green.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Verify at https://hex.pm/packages/a2a_sdk and https://hexdocs.pm/a2a_sdk.
