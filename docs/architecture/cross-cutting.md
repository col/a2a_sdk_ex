# Cross-cutting concerns

[← Architecture](../architecture.md)

Concerns that touch multiple components: extensions, identity/auth, telemetry,
errors, and configuration. The v1 tiering of these (must / should / deferred) is
in [Scope and roadmap](scope-and-roadmap.md) and
[ADR-0008](decisions/0008-v1-feature-tiers.md).

## Extensions

A2A protocol extensions let an agent advertise optional behaviours and clients
opt into them per request.

- The agent card declares supported extensions under
  `capabilities.extensions`.
- A client opts in via the `A2A-Extensions` request header (comma-separated
  extension URIs).
- `A2A.Extensions` parses the header into `requested_extensions` on the
  [`RequestContext`](request-handling.md); the executor (or an executor-wrapping
  middleware function) acts on them and the handler echoes the **activated**
  extensions back in the response header.

Implemented as executor-wrapping middleware — a decorator function around
`execute/2` — matching the reference SDKs' pattern. Cheap, and included in v1.

## Identity & authentication

The SDK **models** identity but does not implement authentication — actual
credential verification stays in the host's plug pipeline, exactly as the Python
and JS SDKs leave it to the web framework.

- `A2A.User` — a struct with `authenticated?` and `id`/`name`, plus arbitrary
  claims.
- A `user_resolver` hook — `(Plug.Conn.t() -> A2A.User.t())` — configured at
  init. The host authenticates however it likes (Bearer/JWT/session in its own
  plug), and the resolver converts the request into an `A2A.User`.
- The resolved user is placed on the [`RequestContext`](request-handling.md) so
  the executor sees its caller, and feeds the owner resolver that scopes the
  [`TaskStore`](persistence.md).

Default resolver returns an unauthenticated user (single-tenant, open agents work
with zero config).

## Telemetry

Observability uses `:telemetry` — the idiomatic Elixir standard — instead of the
OpenTelemetry decorators the Python SDK bakes in. We **emit events**; users
attach whatever handlers/exporters they want (including an OTel bridge).

Planned event families:

| Event | When |
| --- | --- |
| `[:a2a, :execution, :start \| :stop \| :exception]` | An execution process runs / finishes / crashes (with `task_id`, duration, final state) |
| `[:a2a, :rpc, :start \| :stop \| :exception]` | A `RequestHandler` call |
| `[:a2a, :push, :sent \| :failed]` | Webhook delivery outcome |

This keeps the core dependency-free while giving production users first-class
metrics, tracing, and logging via their existing telemetry stack.

## Errors

A semantic error set, `A2A.Error`, decoupled from any transport — with
per-transport rendering:

| Semantic error | Meaning |
| --- | --- |
| `:task_not_found` | Unknown `task_id` |
| `:task_not_cancelable` | Task already terminal |
| `:unsupported_operation` | Method not supported by this agent |
| `:content_type_not_supported` | Unacceptable input/output mode |
| `:push_not_supported` | Agent does not advertise push notifications |
| `:invalid_agent_response` | Executor produced an invalid event |
| `:extension_required` | A required extension was not activated |

Rendering:

- `A2A.Error.to_jsonrpc/1` — **landed** — renders a JSON-RPC error object
  (`%{"code" => integer, "message" => binary, optional "data" => term}`). Code
  mapping:

  | Semantic error | JSON-RPC code |
  | --- | --- |
  | `:task_not_found` | `-32001` |
  | `:task_not_continuable` / `:task_in_progress` / `:task_not_cancelable` | `-32002` |
  | `:unsupported_operation` | `-32004` |
  | `:content_type_not_supported` | `-32005` |
  | `:invalid_agent_response` | `-32006` |
  | internal / timeout / unmapped | `-32603` |

- `A2A.Error.to_rest/1` → HTTP status + JSON body. **Pending** the REST
  transport phase — not yet implemented.

Errors are **tagged structs, not exceptions on the hot path** — the handler
returns `{:error, %A2A.Error{}}` and the transport renders it. Unexpected raises
in executor code are caught and mapped to a `failed` task (see
[Process model](process-model.md#crash-handling)), which is a task-state outcome
rather than an RPC error.

## Configuration

Everything pluggable is passed at supervisor / handler init — there is **no
required global configuration**, so the whole tree composes inside a host app
(invariant 7 in the [top-level doc](../architecture.md)):

| Option | Default |
| --- | --- |
| `pubsub` (name) | starts `A2A.PubSub`; pass host's `MyApp.PubSub` to reuse |
| `task_store` | `A2A.Server.TaskStore.ETS` |
| `push_config_store` | `A2A.Server.PushConfigStore.ETS` |
| `push_http_client` | `Req` (if present) |
| `user_resolver` | unauthenticated user |
| `id_generator` | UUID v4 |
| `agent_card` | required |
| `executor` | required |

## Deferred cross-cutting features

- **Agent card signing** (JWS + RFC-8785 JCS canonicalization) — deferred to a
  later release; it needs real crypto + canonicalization work and is only needed
  by clients verifying card authenticity, not by an agent hosting itself. See
  [Scope and roadmap](scope-and-roadmap.md).

## Related

- [Request handling](request-handling.md), [Persistence](persistence.md),
  [Streaming and events](streaming-and-events.md).
- [ADR-0008](decisions/0008-v1-feature-tiers.md).
