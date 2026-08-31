# HTTP transport — Phase 2: REST binding + `cancel` and `list`

Status: approved (brainstorm 2026-08-30)
Branch: `throng/AA-13`

## Purpose

The JSON-RPC binding landed last phase over one transport-agnostic
`A2A.Server.RequestHandler`. Two things remain before the v1 HTTP surface is
complete: the **second wire binding — HTTP+JSON/REST** — and the **two runtime
actions the handler still doesn't serve, `cancel` and `list`**. This phase
delivers both.

`cancel` and `list` are not merely wire work — the runtime does not implement
them yet. `cancel` needs the execution process to be signalable *while the
author's `execute/2` is running* (it currently is not — see below); `list`
needs the task store to answer a filtered, ordered, paginated query. So this
phase touches the runtime (`A2A.Server.*`), the JSON-RPC dispatch, and adds the
REST binding on top.

Per [ADR-0003](../../architecture/decisions/0003-jsonrpc-and-rest-transports.md)
both bindings sit behind one handler and **SSE is implemented once and reused**;
per [ADR-0010](../../architecture/decisions/0010-jsonrpc-transport-first.md) REST
follows JSON-RPC and reuses the same router, dispatch, SSE mechanics, and error
rendering. This phase realises the REST half of ADR-0003 and closes out the two
methods ADR-0010 left "an honest reflection of current capability."

The wire binding introduces no new protocol semantics: it parses the wire form
into the existing typed requests, calls the handler, and renders the typed
result (or an `A2A.Error`) back. The protocol semantics that *are* new
(`cancel`, `list`) live entirely behind the `RequestHandler` boundary.

## Background: what already exists

- **Types** — `A2A.Types.CancelTaskRequest`, `ListTasksRequest`,
  `ListTasksResponse` are all defined with full field specs. No type work.
- **Behaviours declare but don't implement** — `RequestHandler.cancel_task/2`
  and `list_tasks/2` (both `@optional_callbacks`), `TaskStore.list/2`
  (optional), and `AgentExecutor.cancel/2` (optional) are all declared and
  unimplemented.
- **Errors** — `A2A.Error.to_jsonrpc/1` exists; `@codes` already maps
  `task_not_found → -32001`, `task_not_cancelable → -32002`,
  `unsupported_operation → -32004`, etc. `to_rest/1` does not exist.
- **Wire** — `A2A.Plug.Router` serves the agent card and `POST /` (JSON-RPC);
  `A2A.Plug.JSONRPC` dispatches four methods; `A2A.Plug.SSE` streams frames but
  **hardcodes the JSON-RPC envelope formatter** (`JSONRPC.stream_frame/2`).

## Scope

### In

**Runtime — cancel:**

- **`A2A.Server.Execution` restructured** to run the author's `execute/2` in a
  **monitored child process**, so the `Execution` GenServer mailbox stays free
  to receive a cancel request mid-execution.
- **`A2A.Server.DefaultHandler.cancel_task/2`** — the three-state cancel path
  (live / terminal / persisted-not-live) plus the completes-in-the-race-window
  handling.
- **`A2A.Error.not_cancelable/1`** — constructor for `:task_not_cancelable`.

**Runtime — list:**

- **`A2A.Server.TaskStore.ETS.list/2`** — implements the optional `list/2`.
- **`A2A.Server.DefaultHandler.list_tasks/2`** — filtering, mandated ordering,
  cursor pagination, and per-task history/artifact post-processing.

**Wire — JSON-RPC:**

- **`A2A.Plug.JSONRPC`** gains `tasks/cancel` and `tasks/list` in `@methods`
  plus their `call/4` clauses. No new envelope machinery.

**Wire — REST:**

- **`A2A.Plug.REST`** (new) — the transport-mechanics twin of `A2A.Plug.JSONRPC`:
  build a typed request from path params + query + body via `A2A.JSON`, call the
  handler, tag the result for the router to render. No `Plug.Conn`, no sockets.
- **`A2A.Plug.Router`** gains the six REST routes (proto paths).
- **`A2A.Error.to_rest/1`** — semantic error → `{http_status, body_map}`, body
  as `google.rpc.Status` ProtoJSON.
- **`A2A.Plug.SSE.respond/4`** — a frame-formatter argument so REST streams bare
  `StreamResponse` ProtoJSON while JSON-RPC keeps its envelope. SSE core stays
  single-source (ADR-0003).

**Docs:** ADR-0011; updates to `transports.md`, `request-handling.md`,
`cross-cutting.md` (errors), `CLAUDE.md`, `README`, and the affected moduledocs.

### Out (deferred, additive behind these seams)

- **Push-notification-config REST routes** (`/tasks/{id}/pushNotificationConfigs…`)
  — the runtime implements no push config; wiring routes to unimplemented
  methods would repeat exactly the mismatch ADR-0010 warned against. Deferred to
  the push-config phase.
- **`/{tenant}/…` additional bindings** — scoping is still a single
  `A2A.Scope` (the ETS store is globally named; see CLAUDE.md gotchas), so
  tenant-prefixed routes would be half-wired. Non-tenant routes only this phase;
  the `tenant` request field is carried but not used to vary scope.
- **gRPC, extensions, real auth, telemetry** — later phases, untouched here.

## Design

### 1. Cancellation — `Execution` restructure (the crux)

Today `Execution.handle_continue(:run)` calls `arg.executor.execute(ctx, updater)`
**synchronously**, so the GenServer processes nothing else until `execute/2`
returns and the process stops. A cancel request delivered mid-run would queue
behind `execute/2` and never be handled. Cooperative, concurrent cancellation
therefore requires `execute/2` to run off the GenServer's own reduction.

**New shape.** `handle_continue(:run)` starts the author's `execute/2` in an
**unlinked, monitored** child process (`spawn_monitor`, or a `Task` started with
`:monitor` rather than a link) and returns, leaving the GenServer idle and
responsive. Unlinked is deliberate: an author raise must surface to `Execution`
as a non-normal `:DOWN` it can turn into `TaskUpdater.fail/2`, not as a linked
exit that takes `Execution` down before it can settle the task.

- **Child finishes normally** → `Execution` receives the child `:DOWN` (reason
  `:normal`) and stops with `{:stop, :normal, state}`.
- **Child dies abnormally** (raise / throw / exit) → `Execution` catches the
  non-normal `:DOWN`, calls `TaskUpdater.fail/2` with the reason (moving the
  existing `rescue`/`catch` semantics from inline to DOWN-handling), then stops
  normally. A crash inside `execute/2` must not restart execution (still
  `restart: :temporary`).

This **preserves the `monitor: pid` contract** every consumer relies on:
`DefaultHandler`'s blocking drain and both streaming paths call
`EventStream.stream(task_id, monitor: pid, …)` with the `Execution` pid. Because
`Execution` stays alive until its child finishes and only then stops, the
DOWN-based stream termination (ADR-0009) fires exactly as before. The child pid
is internal to `Execution` and never leaves it.

**Cancel handling.** New `handle_call(:cancel, _from, state)`:

1. If the task is already terminal (re-check via the updater's current task
   projection), reply `{:error, not_cancelable}` without touching the child.
2. Otherwise, if `executor` exports `cancel/2`, invoke
   `executor.cancel(ctx, updater)` — the author may emit their own terminal
   (e.g. a custom final message, or even a late `complete`). Respect it.
3. If the task is still non-terminal after the hook, settle `:canceled` via
   `TaskUpdater` (the SDK default — authoritative when the author declines to
   settle).
4. Shut the child down (it is either done or being abandoned), reply
   `{:ok, canceled_task}`, and `{:stop, :normal, …}`.

The `TaskUpdater` broadcast from step 3 (or the author's own terminal in step 2)
is what ends any attached SSE stream and unblocks any blocking drain — cancel
integrates with the existing event path rather than side-channeling.

### 2. `DefaultHandler.cancel_task/2`

```
cancel_task(server, %CancelTaskRequest{id: id}):
  case Registry.lookup(server.registry, id) do
    [{pid, _}] ->
      try: GenServer.call(pid, :cancel)   # {:ok, task} | {:error, not_cancelable}
      catch :exit, _ ->                    # process finished in the race window
        reread(server, id)                 # terminal by construction → not_cancelable
    [] ->
      case server.store.get(id, scope) do
        {:ok, task} when terminal?(task) -> {:error, not_cancelable(id)}
        {:ok, task}                       -> settle_canceled_in_store(server, task)
        {:error, :not_found}              -> {:error, not_found(id)}
      end
  end
```

`settle_canceled_in_store/2` handles the persisted-but-not-live case
(`input_required`, or a projection orphaned by an earlier crash): build a
`:canceled` `TaskStatusUpdateEvent` through a `TaskUpdater` seeded with the
stored task, so it persists **and** broadcasts a terminal event (a late
resubscriber then sees canceled). Returns the canceled `Task`.

Race note: a task that completes between `Registry.lookup` and `GenServer.call`
makes the call exit; the re-read returns the now-terminal task and we answer
`task_not_cancelable`, matching the spec ("the task might have already
completed… return `TaskNotCancelableError`").

### 3. `list_tasks/2` + `TaskStore.ETS.list/2`

**Store.** `TaskStore.ETS.list/2` takes a filter map + scope and returns the
in-scope tasks matching the structural filters (`context_id`, `status`,
`status_timestamp_after`). It scans the table (the projection is small; a
full-table match is acceptable for the ETS default) and returns a plain list —
**sorting, cursoring, and truncation stay in the handler**, keeping the store a
dumb query surface and the spec-shaped logic in one tested place.

**Handler.** `list_tasks/2` is spec-faithful (a2a-protocol.org §ListTasks):

- **Filter** by `context_id`, `status`, `status_timestamp_after`, within scope.
- **Order** by task **status timestamp, descending** (most-recently-updated
  first). Tie-break by `task_id` (ascending) so the sort — and therefore the
  cursor — is total and stable.
- **Cursor pagination.** `page_token` is opaque: base64 of the sort key
  `{status_timestamp, task_id}` of the last item returned. The next page is the
  items strictly after the cursor in `(timestamp desc, id asc)` order. A
  malformed/garbage token is rejected as invalid params.
- **`page_size`** default **50**, min **1**, max **100** (clamped).
- **`next_page_token`** is the last item's cursor when a further page exists,
  else **`""`** (empty string, per spec — never null).
- **`total_size`** = count of all filtered matches before pagination.
- **Per-task post-processing** applied to the page: `history_length` truncates
  each task's `history` (keep the most recent N; absent = unbounded);
  `include_artifacts` (default false) drops `artifacts` when not set.

Returns `%ListTasksResponse{tasks:, next_page_token:, page_size:, total_size:}`.

### 4. JSON-RPC dispatch

`A2A.Plug.JSONRPC.@methods` gains:

```elixir
"tasks/cancel" => {CancelTaskRequest, :unary},
"tasks/list"   => {ListTasksRequest, :unary}
```

with two `call/4` clauses: `cancel_task/2` → `{:reply, result_envelope(id, task)}`;
`list_tasks/2` → `{:reply, result_envelope(id, list_response)}`; both map
`{:error, err}` through the existing `error_from/2`. No other change — cancel and
list are unary, so they reuse the whole existing envelope path.

### 5. REST binding

**Routes** (`A2A.Plug.Router`, proto `google.api.http` paths — the vendored
proto is authoritative; no invented `/v1` prefix):

| Method & path | Handler call | Result | Wire |
| --- | --- | --- | --- |
| `POST /message:send` | `send_message` | `SendMessageResponse` | `application/a2a+json` |
| `POST /message:stream` | `send_message_stream` | frames | **SSE** |
| `GET /tasks/:id` | `get_task` | `Task` | `application/a2a+json` |
| `GET /tasks` | `list_tasks` | `ListTasksResponse` | `application/a2a+json` |
| `POST /tasks/:id:cancel` | `cancel_task` | `Task` | `application/a2a+json` |
| `GET /tasks/:id:subscribe` | `resubscribe` | frames | **SSE** |

The `:cancel` / `:subscribe` suffixes are literal trailing tokens on the id
segment (proto `"/tasks/{id=*}:cancel"`). Plug's `:id` segment does not split on
`:`, so the router matches `"/tasks/" <> rest` for the POST/GET verbs and
strips the `":cancel"` / `":subscribe"` suffix to recover the id (exact
match/rewrite finalized in the plan; unit-tested for ids containing no `:`).

**`A2A.Plug.REST`** — mirrors `A2A.Plug.JSONRPC`: for each route, assemble the
typed request (path `id` + parsed query for `list` + JSON body for `send`/`cancel`)
via `A2A.JSON.from_json_map/2`, call `DefaultHandler`, and return
`{:reply, status, struct}` | `{:error, status, body}` | `{:stream, enum}` for the
router to render. Success bodies are `A2A.JSON.encode!/1` with content type
`application/a2a+json`. Query-param decoding for `ListTasksRequest` maps the
snake/camel query keys onto the request struct through the same field specs.

**Errors — `A2A.Error.to_rest/1`.** Returns `{http_status, body_map}`:

- **HTTP status** per spec §5.4: `task_not_found → 404`;
  `task_not_cancelable`, `unsupported_operation`, `content_type_not_supported`,
  `push_notification_not_supported → 400`; `invalid_agent_response`,
  `internal_error → 500`; plus transport-level parse/invalid-params → 400 and
  unknown route → 404.
- **Body** = `google.rpc.Status` ProtoJSON:

  ```json
  {
    "code": 5,
    "message": "task not found: abc",
    "details": [{
      "@type": "type.googleapis.com/google.rpc.ErrorInfo",
      "reason": "TASK_NOT_FOUND",
      "domain": "a2a-protocol.org",
      "metadata": {"task_id": "abc"}
    }]
  }
  ```

  where `code` is the canonical **`google.rpc.Code`** integer (NOT_FOUND=5,
  INVALID_ARGUMENT=3, INTERNAL=13, …) — distinct from the HTTP status and from
  the JSON-RPC code; `reason` is the error atom upcased to UPPER_SNAKE_CASE;
  `metadata` is stringified from `A2A.Error.data`. A small
  `atom → {http_status, grpc_code, reason}` table in `A2A.Error` is the single
  source, keeping `to_jsonrpc/1` and `to_rest/1` two projections of one map.

**SSE reuse — `A2A.Plug.SSE.respond/4`.** Add a frame-formatter argument
(defaulting to the current JSON-RPC `stream_frame/2`, so the existing call and
tests are unchanged). REST passes a formatter that emits the bare
`StreamResponse` ProtoJSON (`A2A.JSON.to_json_map/1` + `Jason`), no envelope, no
JSON-RPC `id`. The peek-first / chunk / disconnect mechanics are untouched.

### 6. Error model consolidation

`A2A.Error` currently holds a `@codes` atom→JSON-RPC-int map. This phase widens
it to one table keyed by error atom carrying `{jsonrpc_code, http_status,
grpc_code, reason}`; `to_jsonrpc/1` and `to_rest/1` each read the column they
need. The transport-neutral semantic error set stays the authority
([cross-cutting](../../architecture/cross-cutting.md#errors)); the two renderers
are pure projections.

## Interfaces touched

- `A2A.Server.Execution` — process shape (child-run) + `handle_call(:cancel, …)`.
  Internal module; the `start/3` and registry-name contracts are unchanged.
- `A2A.Server.DefaultHandler` — implements `cancel_task/2`, `list_tasks/2`.
- `A2A.Server.TaskStore.ETS` — implements `list/2`.
- `A2A.Error` — `not_cancelable/1`, `to_rest/1`, widened code table.
- `A2A.Plug.JSONRPC` — two methods added.
- `A2A.Plug.REST` — new.
- `A2A.Plug.Router` — six REST routes added; JSON-RPC `POST /` unchanged.
- `A2A.Plug.SSE` — `respond/3` → `respond/4` (formatter arg, back-compatible).

No changes to `A2A.Types.*`, `A2A.JSON`, `EventStream`, `ResultAssembler`,
`TaskUpdater`, `Supervisor`, or the `A2A.Server` handle struct.

## Testing (TDD)

Everyday `mix test` stays green with no proto toolchain.

- **`execution_test`** — the child-run restructure keeps blocking + streaming
  behaviour identical (regression); a live task cancels and settles `:canceled`;
  an executor with a `cancel/2` hook that emits its own terminal is respected; an
  abnormal child crash still fails the task once (no restart / no double-emit).
- **`default_handler`** cancel — all three states (live, terminal →
  `not_cancelable`, persisted-not-live → canceled + broadcast) and the
  completes-in-race → `not_cancelable`.
- **`default_handler`** list — context/status/timestamp filters; descending
  status-timestamp order with id tiebreak; cursor round-trips across pages;
  `page_size` clamp (1/50/100); `next_page_token == ""` on the last page;
  `total_size`; `history_length` and `include_artifacts` post-processing;
  garbage `page_token` → invalid params.
- **`task_store/ets_test`** — `list/2` scope isolation + structural filters.
- **`json_rpc_test`** — `tasks/cancel`, `tasks/list` dispatch, results, and
  error envelopes.
- **`plug/rest_test`** (new) — every route happy path; `application/a2a+json`
  content type; REST SSE emits bare `StreamResponse` frames (no envelope);
  path-suffix routing for `:cancel`/`:subscribe`; `to_rest/1` status + body for
  each error condition.
- **`error_test`** — `to_rest/1` status/grpc-code/reason table and body shape.

`mix precommit` (format, `--warnings-as-errors`, `credo --strict`, tests,
dialyzer) is the gate.

## Documentation

- **ADR-0011** — REST binding + cancel/list landed (records the `Execution`
  child-run restructure and the deferrals: push-config REST, tenant bindings).
- **`transports.md`** — REST moves from "pending" to "landed"; route table;
  `to_rest/1`.
- **`request-handling.md`** — cancel/list now served; the cancellation model.
- **`cross-cutting.md`** — the REST error rendering (`google.rpc.Status`).
- **`CLAUDE.md`** — status paragraph; move cancel/list/REST out of "deferred."
- **`README`** — REST routes and `curl` recipes.
- Moduledocs on `RequestHandler`, `TaskStore`, `Execution`, `DefaultHandler`.

## References

- [A2A Specification](https://a2a-protocol.org/latest/specification/) — ListTasks
  pagination/ordering; cancel semantics; §5.4 error → HTTP/JSON-RPC codes.
- [A2A spec (canonical markdown)](https://github.com/a2aproject/A2A/blob/main/docs/specification.md).
- [ADR-0003](../../architecture/decisions/0003-jsonrpc-and-rest-transports.md),
  [ADR-0009](../../architecture/decisions/0009-eventstream-termination.md),
  [ADR-0010](../../architecture/decisions/0010-jsonrpc-transport-first.md).
- Vendored `priv/proto/a2a.proto` — `google.api.http` route annotations.
