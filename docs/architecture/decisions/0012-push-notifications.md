# 12. Push notification config CRUD + best-effort delivery engine

Date: 2026-08-31
Status: Accepted

## Context

[ADR-0011](0011-rest-binding-and-cancel-list.md) shipped the REST binding and
`tasks/cancel`/`tasks/list`, but deliberately deferred push-notification-config
routes: "the runtime implements no push config yet; wiring routes to
unimplemented methods would repeat exactly the mismatch ADR-0010 warned
against." [ADR-0008](0008-v1-feature-tiers.md) already committed v1 to push
notifications as a feature tier. This phase closes that gap: config CRUD (both
bindings) plus an actual webhook-delivery engine, so a client can register a
`TaskPushNotificationConfig` and receive the same `StreamResponse` frames an
SSE subscriber would see, over HTTP POST instead.

Two design questions drove the shape: (1) how delivery composes with the
existing PubSub event path without becoming a privileged consumer or a new
side-channel, and (2) how "best-effort" is enforced so one bad webhook (wrong
URL, dead host, slow server) cannot affect task execution, other configs on
the same task, or other tasks entirely.

## Decision

**Config storage — a separate behaviour, not `TaskStore`.**
`A2A.Server.PushConfigStore` is a small behaviour (`put/2`, `get/3`, `list/2`,
`delete/3`) keyed by `{scope, task_id, id}`, with `A2A.Server.PushConfigStore.ETS`
as the default (GenServer-owned ETS table, same shape as `TaskStore.ETS`).
Keeping it separate from `TaskStore` means the `Task` type stays pure — no
`push_config` field bolted onto it — and a custom `TaskStore` implementation
is never forced to also implement push storage. The store is a **dumb upsert
surface**: `id` assignment (when the caller omits one) lives in
`DefaultHandler`, matching the pattern already used for `task_id`/`context_id`
generation.

**Delivery — one dispatcher process per task, subscribing to the existing
topic.** `A2A.Server.PushDispatcher` is a `:temporary` GenServer that
subscribes to the task's `"a2a:task:<task_id>"` PubSub topic — the same topic
an SSE consumer or `resubscribe` attaches to (see
[ADR-0005](0005-pubsub-process-model.md)). It is *just another subscriber*: it
cannot write task state, cannot block the executor, and its failure or absence
never affects execution. `A2A.Server.PushDispatcher.Supervisor` (a
`DynamicSupervisor` + `Registry`, both push-scoped and started only when push
is enabled) makes `ensure_started/2` idempotent — one dispatcher per task,
keyed by `task_id`, started lazily on the first config registration.

For each event, the dispatcher re-reads the task's current config list from
`PushConfigStore` (not a snapshot taken at subscribe time — a config added,
removed, or edited mid-task takes effect on the next event) and delivers to
every webhook **concurrently** (`Task.async_stream/3`), **awaiting all before
processing the next event**. This per-event barrier is deliberate: it gives
per-task delivery ordering (event N+1 is never sent before event N finishes
dispatch) while keeping per-config delivery concurrent and isolated —
`A2A.Test.DelayingSender` and `A2A.Test.PartialRaisingSender` in the test
suite exist specifically to prove a slow or raising config doesn't reorder or
starve a sibling config's delivery. The dispatcher exits normally on the
task's terminal event, or after a 60s idle timeout (belt-and-suspenders — the
terminal event is the expected exit path).

**Best-effort, unconditionally.** `dispatch_one/4` wraps `PushSender.send/3`
in `rescue`/`catch` as well as handling its `{:error, reason}` return; any
outcome besides `:ok` is `Logger.warning` and dropped, never raised, never
retried, never surfaced to the caller of `message/send` or to the executor.
This is the same posture the process model already takes toward slow/dead SSE
subscribers (ADR-0005): a consumer's problems are the consumer's problems.

**Outbound HTTP — a swappable behaviour, `Req` preferred, `:httpc` fallback.**
`A2A.Server.PushSender` is a one-callback behaviour (`send/3`) so a host can
swap in `Finch`/`Tesla`, or (as the test suite does) capture calls without
real HTTP. `A2A.Server.PushSender.Default` serializes the event as a
`StreamResponse` via the existing proto3-JSON codec
(`Content-Type: application/a2a+json` — the same media type REST responses
use), builds one of two auth headers (`Authorization: <scheme> <credentials>`
from `config.authentication` if present, else
`X-A2A-Notification-Token: <token>` from `config.token`, else none), and POSTs
via `Req` if the module is loaded (`Code.ensure_loaded?/1`), falling back to
OTP's built-in `:httpc` otherwise. `req` is an **optional** dependency —
adding push notifications does not force an HTTP client onto every consumer;
projects with no `Req` already in their deps still get delivery via `:httpc`.
Receiver-side verification (JWT/JWKS validation of the webhook payload) is
explicitly the client's responsibility and out of scope for the sender.

`A2A.Server.StreamFrame.of/1` (event struct → `StreamResponse` arm) is
factored out of the SSE path and shared verbatim by the push dispatcher — one
mapping, used by both the pull (SSE) and push (webhook) delivery paths, so
they cannot drift on which `StreamResponse` arm a given event maps to.

**Opt-in, with an explicit unsupported error when off.** Push is disabled by
default. `A2A.Server.Supervisor` accepts `push_notifications: true`, which
starts the push-specific children (config store, `Registry`, dispatcher
`DynamicSupervisor`) and wires `server.push_store`/`push_sender`/`push_timeout`/
`push_url_validator`/`push_registry`/`push_dyn_sup`. All four
`DefaultHandler` push callbacks (`create_push_config/2`, `get_push_config/2`,
`list_push_configs/2`, `delete_push_config/2`) and the inline-config path on
`message/send` guard on `ensure_push_enabled/1` first, returning
`A2A.Error` `:push_notification_not_supported` when the server wasn't
started with push enabled — the same error/gating shape
[ADR-0008](0008-v1-feature-tiers.md) established for other optional
capabilities. A host that enables push at the server level must separately
set `AgentCard.capabilities.push_notifications = true` to *advertise* support
to clients — the runtime flag and the card are independent (a server could
technically support push without advertising it, though there's no reason
to).

**Inline registration on `message/send`.** `SendMessageConfiguration` carries
an optional `task_push_notification_config`; when present (and push is
enabled), `DefaultHandler` registers it exactly as the CRUD `create_push_config`
path would (assign an id if absent, `PushConfigStore.put/2`, ensure a
dispatcher is running) before starting execution. An invalid inline webhook
URL is swallowed (`message/send` still proceeds) rather than failing the
whole call — the config CRUD path validates strictly and returns an error,
because there the config *is* the request.

**SSRF mitigation — a pluggable validator, not a hardcoded blocklist.**
`PushSender.default_url_validator/0` only rejects non-`http`/`https` or
malformed URLs; it does **not** block internal/private address ranges,
because what counts as "internal" is deployment-specific (a control-plane
service legitimately targeting an internal webhook is a normal case in some
deployments). `A2A.Server.Supervisor` accepts `push_url_validator:
(String.t() -> :ok | {:error, term()})`, applied to both CRUD-registered and
inline-registered URLs before persisting. Production deployments **should**
supply a stricter validator (DNS-resolve and reject RFC1918/loopback/
link-local ranges, or an allowlist) — documented as a hook, not built as a
default, per spec §13.2.

**Wire surface — v1.0 slash-style JSON-RPC methods, proto REST routes.**
JSON-RPC: `tasks/pushNotificationConfig/set`, `.../get`, `.../list`,
`.../delete`, dispatched by `A2A.Plug.JSONRPC` like every other method.
REST: `POST/GET /tasks/{task_id}/pushNotificationConfigs`,
`GET/DELETE /tasks/{task_id}/pushNotificationConfigs/{id}` on
`A2A.Plug.Router`, following the vendored proto's `google.api.http`
annotations exactly, same as every other REST route (ADR-0011).

## Consequences

- The v1 feature surface committed in [ADR-0008](0008-v1-feature-tiers.md) now
  has push notifications implemented end-to-end: config CRUD on both bindings,
  inline registration on `message/send`, and real webhook delivery, proven by
  an integration test that runs a real Bandit receiver and asserts a delivered
  `completed` frame (`test/a2a/server/push_e2e_test.exs`, `@moduletag
  :integration`).
- `A2A.Server.PushConfigStore.ETS` is globally named (`name: __MODULE__`),
  inheriting the same single-supervision-tree-at-a-time limitation as
  `A2A.Server.TaskStore.ETS` (see CLAUDE.md's known constraints) — a Phase-1
  limitation, not a push-specific one, and a candidate for the same future fix
  (per-instance table + name).
- Delivery is **best-effort and forward-only**: a dispatcher only sees events
  emitted *after* it starts (which happens on first config registration for
  that task). A config registered mid-task does not retroactively receive
  events already broadcast before it existed — a receiver that needs the full
  history reconciles via `tasks/get`, same as a client that missed part of an
  SSE stream and resubscribes. This mirrors PubSub's existing semantics
  (ADR-0005) rather than adding new replay machinery.
- The per-event delivery barrier means a hung webhook can delay — but,
  bounded by `push_timeout` (+1s slack) via `Task.async_stream`'s
  `on_timeout: :kill_task` — never indefinitely block, that one task's
  subsequent event delivery. It never blocks another task's dispatcher (each
  runs in its own process) or the execution process itself (the dispatcher is
  a plain subscriber).
- Runtime dependency graph gains one **optional** dependency: `req` (falls
  back to OTP's `:httpc`, always available). No new **hard** dependency.
- **Deferred, additive behind these seams:** receiver-side signature/JWT
  verification (client responsibility, out of scope per spec §13); retry
  policies / dead-letter handling for failed deliveries (current behavior:
  log and drop — a fast-follow could add bounded retry behind the same
  `PushSender` seam without changing the dispatcher); `/{tenant}/…` scoping
  (still deferred from ADR-0011, applies equally here).
