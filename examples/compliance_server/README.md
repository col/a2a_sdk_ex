# Compliance Server — A2A Elixir SDK example

The agent the [A2A TCK](https://github.com/a2aproject/a2a-tck) runs against.
`scripts/run_tck.sh` boots this app, waits for its agent card, and points the
TCK at it.

It exists alongside [`../echo_server`](../echo_server), which stays deliberately
minimal — the smallest readable "how do I write an A2A agent" example. This one
has the opposite goal: advertise every capability the SDK can serve and
implement every behaviour the TCK asks for, so a compliance run measures the
*library* rather than the example's gaps.

## Run

```bash
cd examples/compliance_server
mix deps.get
mix run --no-halt
```

Serves both bindings on port 5002 — deliberately not the echo server's 5001,
so both examples can run at once. Override with
`config :compliance_server, port: <n>`.

## The SUT scenario contract

The TCK has no side-channel for telling an agent how to behave. It encodes the
request **in the `messageId`** — `tck-<scenario>-<session>` — and treats its own
Gherkin files as the source of truth:

- `a2a-tck/scenarios/core_operations.feature`
- `a2a-tck/scenarios/streaming.feature`

`ComplianceServer.Scenarios` transcribes that table; `ComplianceServer.Executor`
holds one clause per scenario. When the TCK adds a scenario, add the prefix to
`Scenarios` and the clause to `Executor`.

| `messageId` prefix | Behaviour |
| --- | --- |
| `tck-complete-task` | Complete with the message "Hello from TCK" |
| `tck-artifact-text` | Complete with a text artifact |
| `tck-artifact-file` | Complete with a `raw` file part (`output.txt`, `text/plain`) |
| `tck-artifact-file-url` | Complete with a `url` file part |
| `tck-artifact-data` | Complete with a data artifact |
| `tck-input-required` | Leave the task in `input_required` |
| `tck-reject-task` | Reject the task |
| `tck-stream-001/002/003` | Stream `working` → artifact → `completed` |
| `tck-stream-ordering-001` | Same, for event-ordering checks |
| `tck-stream-artifact-text/-file` | Stream a text / file artifact |
| `tck-stream-artifact-chunked` | Stream two chunks merged into one artifact |
| `test-resubscribe-message-id` | Stay live for 2 × `TCK_STREAMING_TIMEOUT`, then complete |
| anything else | Complete like an ordinary task |

Two ordering rules are load-bearing in the executor:

- **Artifacts before the terminal status.** A task freezes on reaching a
  terminal state, so an artifact emitted after `complete/2` is dropped by
  `A2A.Server.ResultAssembler`.
- **Longest prefix wins.** `tck-artifact-file` is a prefix of
  `tck-artifact-file-url`; matching in declaration order silently resolves every
  file-url request to the plain file scenario.

### Not implemented

`tck-message-response` asks the agent to return a bare `Message` instead of a
`Task`. The SDK has no path for that yet — `A2A.Server.DefaultHandler.send_message/3`
always returns `{:ok, %Task{}}` — so it falls through to the default and
DM-MSG-001 stays red until that lands.

## Tests

```bash
cd examples/compliance_server
mix test
```

Covers the prefix table (including the collision pair) and drives the executor
through a real server to assert the assembled `Task` — the same shape the TCK
inspects. Like the echo server, this app is **not** part of the root project's
`mix test` or `mix precommit`.

The end-to-end gate is the TCK itself; see `docs/tck-compliance.md`.
