# Echo Server — A2A Elixir SDK example

A minimal end-to-end A2A agent: it echoes back whatever text it receives, served
over both the JSON-RPC and REST (`HTTP+JSON`) bindings via `A2A.Standalone`
(Bandit) on port 5001. Both bindings are advertised in the agent card's
`supported_interfaces` and mounted at the same base URL.

## Run

```bash
cd examples/echo_server
mix deps.get
mix run --no-halt
```

## Try it

Fetch the agent card:

```bash
curl -s http://localhost:5001/.well-known/agent-card.json | jq
```

Send a message (blocking):

```bash
curl -s http://localhost:5001/ \
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
curl -N http://localhost:5001/ \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 2, "method": "message/stream",
    "params": {"message": {"messageId": "m2", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}}
  }'
```

Each `data:` line is a JSON-RPC response envelope carrying one stream event.

## REST binding (`HTTP+JSON`)

The same operations are served over the REST transport at the same base URL,
following the vendored proto's `google.api.http` paths. Requests carry the bare
proto-JSON body (no JSON-RPC envelope); responses use `application/a2a+json`.

Send a message (blocking):

```bash
curl -s http://localhost:5001/message:send \
  -H 'content-type: application/json' \
  -d '{
    "message": {"messageId": "m3", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}
  }' | jq
```

The response is a `SendMessageResponse` whose `task` holds the `echo: hello`
artifact.

Stream the same request (Server-Sent Events):

```bash
curl -N http://localhost:5001/message:stream \
  -H 'content-type: application/json' \
  -d '{
    "message": {"messageId": "m4", "role": "ROLE_USER",
      "parts": [{"text": "hello"}]}
  }'
```

Fetch a task by id:

```bash
curl -s http://localhost:5001/tasks/<task-id> | jq
```

Here each `data:` line is a bare `StreamResponse` (no envelope).
