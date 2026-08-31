# Push Notification Support — Design

**Status:** Proposed
**Date:** 2026-08-31
**Branch:** `throng/AA-16`
**Related:** ADR-0012 (to be written), builds on ADR-0009 (EventStream), ADR-0010
(JSON-RPC transport), ADR-0011 (REST binding, cancel/list)

## 1. Summary

Add A2A **push notification** support to the server runtime: clients register
one or more webhook configurations against a task, and the server **POSTs task
events** to those webhooks as the task progresses. This is the full feature —
both halves:

- **(A) Config management** — the four config operations (`set` / `get` /
  `list` / `delete`), persisted in a new `A2A.Server.PushConfigStore`, wired to
  both the JSON-RPC and REST bindings.
- **(B) The delivery engine** — a per-task dispatcher that subscribes to the
  task's existing PubSub topic and delivers each event to the registered
  webhooks through a swappable `A2A.Server.PushSender` behaviour (default uses
  `Req` when present, `:httpc` otherwise).

Push is **opt-in per server** and **best-effort**: delivery failures are logged,
never raised into the task path.

## 2. Spec grounding

Confirmed against the [A2A specification](https://a2a-protocol.org/latest/specification/)
and the reference [`a2a-js`](https://github.com/a2aproject/a2a-js) server
implementation (`src/server/push_notification/`):

- **Trigger:** the server fires on **every** task event. The reference sender's
  `send()` is invoked for each `StreamResponse` (task / status-update /
  artifact-update / message). There is **no** "only terminal" policy knob.
- **Payload:** the webhook body is the **`StreamResponse`** serialized as
  proto3-JSON, with `Content-Type: application/a2a+json` — *not* a bare `Task`
  snapshot. (This repo already has the `StreamResponse` union and
  `A2A.Plug.REST.content_type/0`.)
- **Auth headers:** if `config.authentication` has both `scheme` and
  `credentials` → `Authorization: <scheme> <credentials>`. Otherwise, if
  `config.token` is set → `X-A2A-Notification-Token: <token>`.
- **Ordering:** the reference chains dispatches **per task-id** so a task's
  notifications are delivered in order; different tasks proceed concurrently;
  within one event, a task's multiple webhooks fire concurrently.
- **Timeout:** each dispatch is bounded (reference default 5s); failures are
  logged, not raised.
- **Capability + gating:** support is advertised via
  `AgentCard.capabilities.push_notifications`. When a server does not support
  push, the config operations **MUST** return `PushNotificationNotSupportedError`.
- **Method naming:** current A2A v1.0 JSON-RPC uses camelCase RPC names
  (`CreateTaskPushNotificationConfig`…), but **this repo's JSON-RPC binding
  already uses the v0.3 slash-style names** (`message/send`, `tasks/get`,
  `tasks/cancel`, `tasks/list`, `tasks/resubscribe`). For internal consistency
  we match that convention:
  `tasks/pushNotificationConfig/set|get|list|delete`.
- **REST routes:** taken directly from the vendored proto's `google.api.http`
  annotations: `POST|GET|DELETE /tasks/{task_id}/pushNotificationConfigs[/{id}]`.
- **Security (§13.2):** SSRF protection is the **server's** responsibility
  (validate webhook URLs, avoid internal addresses). Receiver-side JWT/JWKS
  verification is the **client's** responsibility and is out of scope for this
  server SDK (documented, not implemented).

## 3. What already exists

All the **types** are present (`lib/a2a/types/push_notifications.ex`):
`TaskPushNotificationConfig`, `AuthenticationInfo`, and the Get / Delete / List
request structs + `ListTaskPushNotificationConfigsResponse`.
`SendMessageConfiguration.task_push_notification_config` already carries an
inline config on `message/send`. The error table
(`lib/a2a/error.ex`) already has `push_notification_not_supported` wired for
both JSON-RPC and REST projections.

**Missing** (what this work delivers): config storage, handler callbacks,
transport wiring for the four config ops, and the delivery engine.

## 4. Architecture

Five new units, each with one clear purpose:

### 4.1 `A2A.Server.PushConfigStore` (behaviour) + `.ETS` (default)

Persistence for push configs, **separate** from `TaskStore` (keeps the `Task`
type pure and honors interface segregation — a custom `TaskStore` implementer is
not forced to implement push storage). Mirrors the `TaskStore` shape.

```elixir
@callback put(TaskPushNotificationConfig.t(), A2A.Scope.t()) ::
            {:ok, TaskPushNotificationConfig.t()} | {:error, term()}
@callback get(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) ::
            {:ok, TaskPushNotificationConfig.t()} | {:error, :not_found}
@callback list(task_id :: String.t(), A2A.Scope.t()) ::
            {:ok, [TaskPushNotificationConfig.t()]}
@callback delete(task_id :: String.t(), id :: String.t(), A2A.Scope.t()) ::
            :ok | {:error, :not_found}
```

- Keyed by `{scope, task_id, id}`.
- `put/2` **assigns an `id`** (via the server's `id_generator`) when the client
  omits one; `set` is an **upsert** on `{task_id, id}` (spec: "MUST assign …
  id"). Returns the stored config (with id populated) so `set` can echo it back.
- `.ETS` is a **named, per-server** table started in the supervision tree
  alongside the `TaskStore`. (Shares the `TaskStore.ETS`'s known global-naming
  limitation — see §9; the same "one tree at a time" constraint already applies.)

### 4.2 `A2A.Server.PushSender` (behaviour) + `.Default` (impl)

The outbound-HTTP boundary. Single callback:

```elixir
@callback send(TaskPushNotificationConfig.t(), StreamResponse.t(), keyword()) ::
            :ok | {:error, term()}
```

`A2A.Server.PushSender.Default`:

- Serializes the `StreamResponse` via `A2A.JSON.encode!/1`; body +
  `Content-Type: application/a2a+json`.
- Builds auth headers per §2 (Authorization from `authentication`, else
  `X-A2A-Notification-Token` from `token`).
- Uses **`Req`** if the module is loaded (`Code.ensure_loaded?/1`), else falls
  back to OTP's **`:httpc`**. `Req` becomes an **optional** dep (`optional:
  true`, like `bandit`); the base runtime graph (jason, phoenix_pubsub, plug) is
  unchanged.
- Per-request **timeout** (default 5s, configurable). Returns `{:error, reason}`
  on non-2xx or transport failure — the caller logs it.

### 4.3 `A2A.Server.PushDispatcher` (per-task GenServer)

One dispatcher process **per task that has ≥1 config**. Responsibilities:

- On start, **subscribe to the task's existing PubSub topic** (`Events.subscribe/2`)
  — the same per-task topic the streaming path uses. No new shared topic.
- On each received `Events.Event`, re-read the task's configs from the
  `PushConfigStore` (so configs added mid-task are picked up), map the event's
  domain payload to a `StreamResponse` frame (reuse `DefaultHandler`'s
  `to_frame/1` logic, extracted to a shared helper), and dispatch to **all**
  configs concurrently (`Task.async_stream`, bounded by the per-dispatch
  timeout). **Await all** before processing the next event → per-task ordering.
- Because each task is its own process, a slow/hung webhook consumer blocks only
  **that** task (up to the timeout), never other tasks. Different tasks and a
  task's multiple webhooks are concurrent.
- Shuts down after delivering the task's **terminal** event, or after an idle
  timeout (no events for N ms) as a safety net.
- Delivery failures are logged (`Logger.warning`), never raised.

### 4.4 `A2A.Server.PushDispatcher.Supervisor` + registry

A `DynamicSupervisor` + `Registry` (keyed by `task_id`), started in the server's
supervision tree **only when push is enabled**. An `ensure_started(server,
task_id)` helper starts-or-returns the per-task dispatcher idempotently (via the
registry), called from the two config-registration entry points:

1. Inline config on `message/send` (`configuration.task_push_notification_config`)
   — persisted **and** dispatcher ensured at execution start, **before** the
   executor runs, so early events are caught.
2. `tasks/pushNotificationConfig/set` — persisted **and** dispatcher ensured (if
   the task is live) at set time.

**Honest tradeoff:** a dispatcher only sees events emitted *after* it
subscribes. A config registered after some events have already fired won't
retro-deliver them — inherent to push ("notified from when you register") and
matching the reference's best-effort model. Receivers reconcile via `tasks/get`.

### 4.5 Handler callbacks (`RequestHandler` + `DefaultHandler`)

Four new callbacks on `A2A.Server.RequestHandler` (as `@optional_callbacks`,
consistent with the existing optional streaming/cancel/list set), implemented by
`DefaultHandler`:

```elixir
@callback create_push_config(A2A.Server.t(), TaskPushNotificationConfig.t()) ::
            {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
@callback get_push_config(A2A.Server.t(), GetTaskPushNotificationConfigRequest.t()) ::
            {:ok, TaskPushNotificationConfig.t()} | {:error, A2A.Error.t()}
@callback list_push_configs(A2A.Server.t(), ListTaskPushNotificationConfigsRequest.t()) ::
            {:ok, ListTaskPushNotificationConfigsResponse.t()} | {:error, A2A.Error.t()}
@callback delete_push_config(A2A.Server.t(), DeleteTaskPushNotificationConfigRequest.t()) ::
            {:ok, :deleted} | {:error, A2A.Error.t()}
```

Every callback first checks whether push is enabled on the server; if not, it
returns `%A2A.Error{code: :push_notification_not_supported}`. `list` supports the
same page_size/page_token cursor mechanics already used by `list_tasks`
(defaulting to returning all configs for a task if pagination is not exercised —
config counts per task are small).

## 5. Data flow

```
message/send (with configuration.task_push_notification_config)
  └─ DefaultHandler.send_message
       ├─ PushConfigStore.put(config)          # persist (id assigned)
       ├─ PushDispatcher.ensure_started(task)   # subscribe BEFORE executor runs
       └─ start_execution → executor emits events
                                    │
   TaskUpdater.emit ──broadcast──> per-task PubSub topic
                                    │            │
                     EventStream (streaming) ◄───┤
                     PushDispatcher       ◄───────┘
                        └─ per event: load configs → to_frame → PushSender.send(→ all webhooks)
                                                                       │
                                                          POST application/a2a+json → webhook URL
```

`tasks/pushNotificationConfig/set` follows the same persist + ensure_started
path without starting an execution.

## 6. Transport wiring

### JSON-RPC (`A2A.Plug.JSONRPC`)

Add to the `@methods` map (params typed via `A2A.JSON.from_json_map/2`, matching
the v1.0 proto request shapes):

| Method | Params type | Result |
| --- | --- | --- |
| `tasks/pushNotificationConfig/set` | `TaskPushNotificationConfig` | `TaskPushNotificationConfig` (with id) |
| `tasks/pushNotificationConfig/get` | `GetTaskPushNotificationConfigRequest` | `TaskPushNotificationConfig` |
| `tasks/pushNotificationConfig/list` | `ListTaskPushNotificationConfigsRequest` | `ListTaskPushNotificationConfigsResponse` |
| `tasks/pushNotificationConfig/delete` | `DeleteTaskPushNotificationConfigRequest` | `null` (success) |

All are `:unary`. Errors render via `A2A.Error.to_jsonrpc/1`.

### REST (`A2A.Plug.REST` + `A2A.Plug.Router`)

Routes from the vendored proto, `application/a2a+json` bodies:

| Verb + path | Op |
| --- | --- |
| `POST /tasks/:task_id/pushNotificationConfigs` | set (create) |
| `GET  /tasks/:task_id/pushNotificationConfigs` | list |
| `GET  /tasks/:task_id/pushNotificationConfigs/:id` | get |
| `DELETE /tasks/:task_id/pushNotificationConfigs/:id` | delete |

Errors render via `A2A.Error.to_rest/1` (`google.rpc.Status` body). Router notes:
the existing router escapes `:` in `message\\:send` etc.; these new routes are
plain path segments and nest cleanly under `/tasks/:task_id/...`.

## 7. Server configuration

New options on `A2A.Server.Supervisor` → new fields on the `A2A.Server` struct:

- `push_notifications: boolean()` (default `false`) — master enable. When true,
  the `PushConfigStore`, `PushSender`, and `PushDispatcher.Supervisor` join the
  tree, and the four config ops become live.
- `push_store: module()` (default `A2A.Server.PushConfigStore.ETS`).
- `push_sender: module()` (default `A2A.Server.PushSender.Default`).
- `push_timeout: timeout()` (default `5_000`) — per-dispatch HTTP timeout.
- `push_url_validator: (String.t() -> :ok | {:error, term()}) | nil` (default a
  permissive validator that only rejects non-`http(s)`/malformed URLs). Runs at
  `set`/config-registration time; a rejected URL fails the op with
  `:invalid_params`. Documented: **production deployments should supply a
  stricter validator** blocking internal ranges (SSRF, §13.2).

Enabling push does **not** auto-set `AgentCard.capabilities.push_notifications` —
the host owns their card; documented as a required step to advertise support.

## 8. Error handling & security

- Push disabled → all four ops return `:push_notification_not_supported`.
- Unknown `{task_id, id}` on **get** → `:task_not_found` (reuses the existing
  not-found projection; there is no distinct config-not-found A2A code).
- Unknown `{task_id, id}` on **delete** → **idempotent success** (`:deleted`),
  not an error. This is deliberate: it matches the reference Python and JS A2A
  SDKs' delete semantics and standard HTTP `DELETE` idempotency (deleting an
  already-absent resource is not itself an error).
- URL validation failure on set → `:invalid_params`.
- Delivery failures (non-2xx, timeout, transport error) are **logged and
  swallowed** — best-effort; never surfaced to the task or the caller.
- SSRF: server-side URL validation hook (§7). Receiver-side auth verification:
  documented as client responsibility, out of scope.

## 9. Known constraints / gotchas

- **Per-server global naming.** `PushConfigStore.ETS` and the dispatcher
  registry/supervisor are named after the server, inheriting the same
  "two `A2A.Server.Supervisor` trees can't run at once" limitation the
  `TaskStore.ETS` already documents. No new class of constraint.
- **Dispatcher subscription timing.** See §4.4 — configs registered after events
  fire won't retro-deliver (best-effort by design).
- **`Req` optionality.** With neither `Req` nor a custom sender, delivery uses
  `:httpc` (always available in OTP). No hard dep is added.

## 10. Testing strategy (TDD)

Everyday `mix test` stays green with no extra toolchain and **no real network**:

- **`PushConfigStore.ETS`** — put/get/list/delete, id assignment, upsert,
  scope isolation.
- **`PushSender`** — inject a **test double** sender (capture calls) via
  `push_sender:` to assert (config, frame) pairs, header construction, and
  ordering, without HTTP. A thin, separately-tagged test may exercise the real
  `:httpc`/`Req` path against a local `Bandit`/`Plug` test endpoint.
- **`PushDispatcher`** — drive `TaskUpdater` events through a real PubSub and a
  capturing sender; assert per-task ordering, concurrency isolation (a blocked
  webhook for task A doesn't stall task B), terminal shutdown, and mid-task
  config pickup.
- **Handler callbacks** — enabled vs disabled (`not_supported`), url-validator
  rejection, not-found.
- **Transport** — JSON-RPC method dispatch + REST routes for all four ops,
  success and error rendering, round-tripped through `A2A.JSON`.
- **End-to-end** — `message/send` with an inline config → capturing sender
  observes the frames the streaming path also produces.

`examples/echo_server/` gains a commented push-config demonstration (optional,
not part of `mix test`).

## 11. Out of scope (deferred, consistent with the repo)

- `/{tenant}/…` multi-tenant routing (deferred repo-wide).
- Receiver-side JWT/JWKS verification (client responsibility).
- Delivery retries / durable outbox / global outbound-concurrency cap — a shared
  `Task.Supervisor` with `max_children` can be slotted in front of `PushSender`
  later without changing the per-task-dispatcher shape. Noted as a future knob.

## 12. Documentation

- New **ADR-0012** recording the delivery-engine decision (per-task dispatcher;
  best-effort; `PushSender`/`PushConfigStore` behaviours; optional `Req`).
- Update `docs/architecture/` (process-model, transports, request-handling,
  cross-cutting) and `CLAUDE.md` (remove push from the deferred list; add the
  new modules + constraints), and `README.md`.
