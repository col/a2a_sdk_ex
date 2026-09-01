# 11. REST binding, `tasks/cancel`, and `tasks/list` land

Date: 2026-08-30
Status: Accepted
Superseded in part by [ADR-0013](0013-spec-faithful-error-representation.md)
(REST error body and content type).

## Context

[ADR-0010](0010-jsonrpc-transport-first.md) shipped JSON-RPC first and left
three things "an honest reflection of current capability": the REST/HTTP+JSON
binding was unimplemented, and the runtime itself didn't yet serve
`tasks/cancel` or `tasks/list` (both declared `@optional_callbacks` on
`RequestHandler`, unimplemented). [ADR-0003](0003-jsonrpc-and-rest-transports.md)
had already committed v1 to both bindings behind one handler; this phase
closes that gap.

`cancel` and `list` are not pure wire work — the runtime didn't implement the
semantics yet. `cancel` needs the execution process to stay responsive to a
cancel signal *while the author's `execute/2` is running*, which the previous
`Execution` shape (a synchronous call inside `handle_continue`) could not do.
`list` needs the task store to answer a filtered, ordered, paginated query.

## Decision

Ship all three together: the REST binding, `DefaultHandler.cancel_task/2`, and
`DefaultHandler.list_tasks/2`, plus the `Execution` restructure the cancel path
requires.

**REST binding.** `A2A.Plug.REST` is the transport-mechanics twin of
`A2A.Plug.JSONRPC`: it builds a typed request from path params, query, and
body via `A2A.JSON`, calls `A2A.Server.DefaultHandler`, and tags the result for
`A2A.Plug.Router` to render. Routes follow the vendored proto's
`google.api.http` annotations exactly — no invented `/v1` prefix:

| Method & path | Handler call | Result |
| --- | --- | --- |
| `POST /message:send` | `send_message` | `SendMessageResponse` (`application/a2a+json`) |
| `POST /message:stream` | `send_message_stream` | SSE, bare `StreamResponse` frames |
| `GET /tasks/:id` | `get_task` | `Task` (`application/a2a+json`) |
| `GET /tasks` | `list_tasks` | `ListTasksResponse` (`application/a2a+json`) |
| `POST /tasks/:id:cancel` | `cancel_task` | `Task` (`application/a2a+json`) |
| `GET /tasks/:id:subscribe` | `resubscribe` | SSE, bare `StreamResponse` frames |

Success bodies are `application/a2a+json`, proto3-JSON via `A2A.JSON`. Errors
render through `A2A.Error.to_rest/1`, which returns `{http_status, body}`
where `body` is `google.rpc.Status` ProtoJSON — `code` (canonical
`google.rpc.Code` int), `message`, and a `details` array carrying one
`google.rpc.ErrorInfo` (`reason` upper-snake, `domain: "a2a-protocol.org"`,
`metadata` stringified from `A2A.Error.data`). Status mapping (spec §5.4):
`task_not_found → 404`; `task_not_cancelable`, `task_not_continuable`,
`unsupported_operation`, `content_type_not_supported`,
`push_notification_not_supported` → `400`; `task_in_progress → 409`;
`invalid_agent_response`, `internal_error → 500`; `timeout → 504`; plus
transport-level parse/invalid-params errors → `400` and unknown routes →
`404`. `A2A.Error` now holds one table keyed by error atom
(`{jsonrpc, http, grpc, reason}`); `to_jsonrpc/1` and `to_rest/1` are pure
projections of it, so the two renderers cannot drift.

SSE is reused, not reimplemented: `A2A.Plug.SSE.respond/4` gained a
frame-formatter argument (`respond/3` still defaults to the JSON-RPC
envelope), so REST passes a formatter that emits the bare `StreamResponse`
ProtoJSON with no envelope and no JSON-RPC `id`. The peek-first / chunk /
disconnect mechanics are untouched — SSE stays implemented once, per
ADR-0003.

One wire-level nuance: Plug's router syntax treats a mid-segment `:` as a
dynamic-param marker (`foo:bar` binds a param named `bar`), so an unescaped
`/message:send` would collide with `/message:stream` (both compiling to
"message" + capture-rest). The proto's literal `:send`/`:stream`/`:cancel`/
`:subscribe` suffixes are therefore written escaped in the router
(`post "/message\:send"`) or recovered by matching the `:id` segment and
stripping the known suffix (`:cancel`, `:subscribe`) in the handler body.

**`Execution` restructure.** `handle_continue(:run)` used to call the
author's `execute/2` synchronously, so the GenServer processed nothing else —
including a cancel request — until `execute/2` returned. Cooperative
cancellation needs the GenServer's mailbox free while the author's code runs.
`Execution` now starts `execute/2` in an **unlinked, monitored child process**
and returns immediately, leaving the GenServer idle and responsive. Unlinked
is deliberate: an author raise must surface as a non-normal child `:DOWN` that
`Execution` turns into `TaskUpdater.fail/2`, not as a linked exit that takes
`Execution` down before it can settle the task. The `monitor: pid` contract
every consumer relies on (`DefaultHandler`'s blocking drain, both streaming
paths, via `EventStream.stream(task_id, monitor: pid, …)`) is preserved
unchanged — `Execution` stays alive until its child finishes and only then
stops, so the DOWN-based stream termination (ADR-0009) fires exactly as
before. The child pid never leaves `Execution`.

**Cancellation model — cooperative but authoritative.** `handle_call(:cancel,
…)` on `Execution`:

1. Re-reads the task from the store (a fresh read, not the updater's cached
   projection) to decide terminality — a task that completed in the race
   window between the caller's `Registry.lookup` and this call must not be
   overwritten with `:canceled`. If already terminal, reply
   `{:error, not_cancelable}` without touching the child.
2. Otherwise kills the in-flight child, then — if the author's executor
   exports `cancel/2` — invokes it. The author's hook is respected: it may
   emit its own terminal (a custom final message, even a late `complete`).
3. If the task is still non-terminal after the hook, the SDK settles
   `:canceled` itself — the default, authoritative outcome when the author
   declines to settle.
4. Replies `{:ok, canceled_task}` and stops normally.

`DefaultHandler.cancel_task/2` looks up the task by `Registry`: a live
execution gets the `GenServer.call(pid, :cancel)` path above; a
`{:noproc, _}` or `{:normal, _}` exit (the process finished in the race
window) falls back to a fresh store read, which is terminal by construction
and answers `task_not_cancelable`; no registry entry falls back to the store
directly — terminal → `task_not_cancelable`, non-terminal (e.g.
`input_required`, or a projection orphaned by an earlier crash) → settle
`:canceled` in the store via a seeded `TaskUpdater` (persists and broadcasts,
so a late resubscriber sees it), missing → `task_not_found`. `A2A.Error.not_cancelable/1`
is the new constructor for `:task_not_cancelable`.

**`list_tasks/2` + `TaskStore.ETS.list/2`.** The store's `list/2` is a dumb
query surface: it scans the (scoped) ETS table for structural filter matches
(`context_id`, `status`, `status_timestamp_after`) and returns a plain list —
sorting, cursoring, and truncation stay in the handler, spec-shaped logic in
one tested place. `DefaultHandler.list_tasks/2` is spec-faithful
(a2a-protocol.org §ListTasks):

- Order by task **status timestamp, descending** (most-recently-updated
  first), tie-broken by `task_id` ascending, so the sort — and the cursor — is
  total and stable.
- `page_token` is an opaque, base64-encoded `{status_timestamp, task_id}`
  cursor; the next page is items strictly after it in `(timestamp desc, id
  asc)` order. A malformed token is rejected as invalid params.
- `page_size` defaults to **50**, clamped to **1..100**.
- `next_page_token` is the last item's cursor when a further page exists,
  else `""` (empty string, per spec — never null).
- `total_size` is the count of all filtered matches before pagination.
- Per-task post-processing on the returned page: `history_length` truncates
  `history` to the most recent N (absent = unbounded); `include_artifacts`
  (default false) drops `artifacts` when unset.

## Consequences

- The v1 HTTP surface committed in ADR-0003 is now complete for both
  bindings' non-push, non-tenant routes: JSON-RPC and REST both expose
  `message/send`, `message/stream`, `tasks/get`, `tasks/cancel`,
  `tasks/list`, and `tasks/resubscribe`.
- `Execution`'s external contract (`start/3`, the registry-name convention,
  the `monitor: pid` guarantee) is unchanged — the child-run restructure is
  internal. No consumer of `EventStream` needed to change.
- Cancellation integrates with the existing event path rather than
  side-channeling: the `TaskUpdater` broadcast from the SDK-default settle (or
  the author's own terminal) is what ends any attached SSE stream and unblocks
  any blocking drain.
- `A2A.Error`'s widened one-table model (`{jsonrpc, http, grpc, reason}` per
  atom) is now the single source for both `to_jsonrpc/1` and `to_rest/1` —
  adding a new semantic error only means adding one row.
- **Deferred, additive behind these seams:**
  - **Push-notification-config REST routes**
    (`/tasks/{id}/pushNotificationConfigs…`) — the runtime implements no push
    config yet; wiring routes to unimplemented methods would repeat exactly
    the mismatch ADR-0010 warned against. Deferred to the push-config phase.
  - **`/{tenant}/…` additional bindings** — scoping is still a single
    `A2A.Scope` (the ETS store is globally named; see CLAUDE.md's known
    constraints). Non-tenant routes only this phase; the `tenant` request
    field is carried but not used to vary scope.
  - gRPC, extensions, real auth, telemetry remain untouched, as before.
