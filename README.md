# a2a_sdk_ex

An Elixir SDK for building [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/v1.0.0/specification/)
servers — agentic applications that expose their capabilities over A2A, built on
OTP for first-class streaming, cancellation, resumption, and webhook delivery.

A peer of the official [Python](https://github.com/a2aproject/a2a-python) and
[JavaScript](https://github.com/a2aproject/a2a-js) SDKs — same protocol, same
architectural seams — but designed for the Elixir/OTP ecosystem rather than
ported line-by-line.

## Try it

Both HTTP bindings are mounted by [`examples/echo_server/`](examples/echo_server)
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

REST — same call, resource-style, `application/json`:

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
support — see [ADR-0012](docs/architecture/decisions/0012-push-notifications.md).

## Documentation

- **[Architecture overview](docs/architecture.md)** — the high-level map: components, boundaries, invariants.
- Detailed docs under [`docs/architecture/`](docs/architecture/): data model, process model, request handling, transports, streaming & events, persistence, cross-cutting concerns, scope & roadmap.

## Design decisions

The scope and shape of v1 are captured as Architecture Decision Records. 
Full context and consequences for each: [decision records](docs/architecture/decisions/README.md).

## Requirements

- **Elixir 1.18+**
- **Erlang/OTP 26+**

The library is tested in CI across Elixir 1.18 / 1.19 / 1.20, each against the
lowest OTP it supports at or above the OTP 26 floor.


## Compatibility

As of commit SHA: `f5d49108a92ba514ca70018f7340d0f510b267f2`

```
═══════════════════════════════════════════════════════
             A2A TCK Compatibility Report
═══════════════════════════════════════════════════════
SUT: http://localhost:5002
Timestamp: 2026-08-31T21:36:02.349739+00:00

OVERALL COMPATIBILITY: 100.0%

┌─────────────┬────────┬────────┬─────────┬───────┐
│ Level       │ Passed │ Failed │ Skipped │ Total │
├─────────────┼────────┼────────┼─────────┼───────┤
│ MUST        │     82 │     21 │      11 │   114 │
│ SHOULD      │      7 │      4 │       0 │    11 │
│ MAY         │      4 │      0 │       0 │     4 │
└─────────────┴────────┴────────┴─────────┴───────┘

BY TRANSPORT:
  agent_card:    10/10 ✓
  grpc:          0/72 (72 skipped) ✓
  jsonrpc:       95/102 (7 skipped) ✓
  http_json:     90/96 (6 skipped) ✓

═══════════════════════════════════════════════════════
```


## License

Licensed under the [Apache License, Version 2.0](LICENSE).
