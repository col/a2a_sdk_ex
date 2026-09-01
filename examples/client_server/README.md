# Client Server — A2A Elixir SDK example

The integration SUT used by the client SDK's own test suite (see
`test/a2a/client/integration_test.exs` in the main repo). Like `echo_server`
it echoes back whatever text it receives, but it exists specifically to give
the **client** something realistic to talk to: a dual-interface agent card
(`JSONRPC` and `HTTP+JSON` at the same served URL), streaming turned on, and a
simple bearer-token identity resolver feeding an authenticated
`GetExtendedAgentCard`.

## Run

```bash
cd examples/client_server
mix deps.get
mix run --no-halt
```

Serves on port 4010 by default (see `config/config.exs`).

## Identity

`ClientServer.user_from_conn/1` resolves the caller from the
`Authorization: Bearer <token>` header: the token `secret` authenticates as
user `u1`; anything else (including no header) is anonymous. This is a toy
resolver for the example only.

```bash
# public agent card
curl -s http://localhost:4010/.well-known/agent-card.json | jq

# extended card — anonymous (errors: extended card needs auth)
curl -s http://localhost:4010/extendedAgentCard | jq

# extended card — authenticated
curl -s http://localhost:4010/extendedAgentCard \
  -H 'Authorization: Bearer secret' | jq
```

## Send a message

```bash
curl -s http://localhost:4010/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "SendMessage",
    "params": {"message": {"messageId": "m1", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}}
  }' | jq
```

You should see a completed task whose artifact contains `echo: hello`.
