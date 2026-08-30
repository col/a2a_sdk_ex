# Echo Server — A2A Elixir SDK example

A minimal end-to-end A2A agent: it echoes back whatever text it receives, served
over the JSON-RPC binding via `A2A.Standalone` (Bandit) on port 4000.

## Run

```bash
cd examples/echo_server
mix deps.get
mix run --no-halt
```

## Try it

Fetch the agent card:

```bash
curl -s http://localhost:4000/.well-known/agent-card.json | jq
```

Send a message (blocking):

```bash
curl -s http://localhost:4000/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "message/send",
    "params": {"message": {"messageId": "m1", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}}
  }' | jq
```

You should see a completed task whose artifact contains `echo: hello`.

Stream the same request (Server-Sent Events):

```bash
curl -N http://localhost:4000/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 2, "method": "message/stream",
    "params": {"message": {"messageId": "m2", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}}
  }'
```

Each `data:` line is a JSON-RPC response envelope carrying one stream event.
