# Auth Phase — Identity, Ownership Scoping & the Authenticated Extended Card

**Status:** Draft
**Date:** 2026-09-01
**Related:** [`cross-cutting.md`](../../architecture/cross-cutting.md) §Identity &
authentication, [`scope-and-roadmap.md`](../../architecture/scope-and-roadmap.md)
(should-have: *Server-side auth/user model*), the security type surface in
`lib/a2a/types/security.ex`, ADR-0011 (error projections), ADR-0012 (push).

## Summary

The A2A **security type surface is fully landed** — `SecurityScheme`,
`SecurityRequirement`, every OAuth flow, `AgentCard.security_schemes` /
`security_requirements`, `capabilities.extended_agent_card`,
`GetExtendedAgentCardRequest`, and `AuthenticationInfo`. What is missing is the
**runtime** that the architecture docs already designed: the resolved caller
never reaches the executor, storage is never isolated per caller, and the
authenticated extended card is never served.

This phase wires that runtime. It follows the SDK's committed philosophy —
**the SDK models identity and exposes hooks; the host's plug pipeline verifies
credentials** (Bearer/JWT/session), exactly as the Python and JS SDKs do. No
crypto is introduced. Every default preserves today's zero-config, single-tenant,
open-agent behaviour.

Four concerns, one coherent phase:

1. **Identity resolution** — a `user_resolver` hook turns a `Plug.Conn` into an
   `A2A.User`, threaded to the executor via `RequestContext.user`.
2. **Ownership scoping** — an `owner_resolver` derives an `A2A.Scope.owner` from
   the user; the (already owner-keyed) `TaskStore` / `PushConfigStore` isolate
   per owner. Cross-owner access returns `TaskNotFound` — spec-faithful, no info
   leak, no invented error.
3. **Authenticated extended card** — the `GetExtendedAgentCard` operation on both
   bindings, backed by an `extended_agent_card_resolver`.
4. **Push outbound auth** — already implemented in `PushSender.Default`; this
   phase adds explicit tests and documentation. JWT/JWKS notification signing
   stays deferred.

## Motivation

`A2A.User`, `A2A.Scope`, and `RequestContext.user` already exist, and the ETS
stores already key by `{tenant, owner, id}`. But:

- `DefaultHandler.build_context/4` hardcodes `user: A2A.User.anonymous()`
  (`lib/a2a/server/default_handler.ex:378`) — the executor can never see its
  caller.
- `A2A.Server.Supervisor` accepts no `user_resolver`; the plug layer never
  resolves a user, and `dispatch/2` carries none.
- `server.scope` is **static** (set once at init to `A2A.Scope.default()`), so
  `scope.owner` is always `nil` and every caller shares one storage bucket.
- `GetExtendedAgentCard` (RPC) / `GET /extendedAgentCard` (REST) are unrouted;
  the `:extended_agent_card_not_configured` error is defined but never raised.

The persistence layer is already owner-ready. This phase is mostly **wiring**:
populate `scope.owner` per request and thread the resolved user end-to-end.

## Non-goals (explicitly deferred)

- **Credential verification** (Bearer/JWT/session parsing) — the host's plug does
  this; the SDK only consumes the resulting `A2A.User`.
- **Agent-card signing** (JWS + JCS) — already deferred; unchanged.
- **Push JWT/JWKS notification signing** — the agent signing its own outbound
  notifications + a JWKS endpoint is the same asymmetric-crypto class as card
  signing. Deferred to that same future release.
- **`/{tenant}/…` multi-tenant path scoping** — `owner` is the isolation unit for
  now; `tenant` stays `nil`.
- **gRPC binding.**

## Design

### 1. Configuration surface

Three new hooks on `A2A.Server.Supervisor`, stored on the `A2A.Server` struct.
All defaults reproduce current behaviour exactly.

| Option | Type | Default | Purpose |
|---|---|---|---|
| `user_resolver` | `(Plug.Conn.t() -> A2A.User.t())` | `fn _ -> A2A.User.anonymous() end` | Host converts an (already-authenticated) request into an `A2A.User`. Runs in the plug layer. |
| `owner_resolver` | `(A2A.User.t() -> String.t() \| nil)` | `fn _ -> nil end` | Derives `A2A.Scope.owner` for storage isolation. `nil` ⇒ current single-tenant sharing. |
| `extended_agent_card_resolver` | `(A2A.User.t() -> A2A.Types.AgentCard.t() \| nil)` | `nil` | Returns a richer card per caller, or `nil` for "nothing extra". |

The config table in `cross-cutting.md` gains these three rows.

### 2. Identity resolution — `A2A.Plug.Identity`

A router plug alongside `A2A.Plug.ServiceParams`, running **before dispatch**:

- Calls `server.user_resolver.(conn)` and stores the result on
  `conn.private[:a2a_user]`.
- Both bindings read that one private key, so JSON-RPC and REST resolve identity
  identically at a single point.
- **Agent-card discovery is exempt** (same `[".well-known" | _]` carve-out the
  service-params plug uses) — the public card needs no caller.
- The default resolver yields `A2A.User.anonymous()`, so an unconfigured host is
  unaffected.

The resolver is expected to be **total** (never raise) — a host that wants to
reject unauthenticated callers does so in its own plug *before* the A2A router,
returning its own `401`. The SDK does not manufacture a `401`, because A2A has no
"unauthenticated" error in its table and authentication is the host's contract.

### 3. Threading user → per-request scope through the handler

- `A2A.Plug.JSONRPC.dispatch/2` becomes `dispatch/3`, gaining a `user`
  argument; the REST dispatch path gains the same. The router reads
  `conn.private[:a2a_user]` and passes it in.
- The user flows into `RequestContext.user`, replacing the hardcoded
  `A2A.User.anonymous()` in `build_context/4`.
- **The pivotal change:** `server.scope` is static. Each handler operation instead
  computes a **per-request scope**:

  ```elixir
  scope = %A2A.Scope{server.scope | owner: server.owner_resolver.(user)}
  ```

  and uses that scope for **every** `store.*` and `push_store.*` call in the
  operation. This includes the write path:

  - `send_message` / `send_message_stream`: the `Execution` / `TaskUpdater`
    persistence must use the per-request scope (currently `updater_opts[:scope]`
    is `server.scope`) so a created task is saved under its owner.
  - Follow-up turns (`resolve_task/2`) and the blocking drain resolve the task
    under the **same** owner scope, so a continuation finds its predecessor.

  The handler signatures gain the resolved user (or a pre-derived scope). The
  default `owner_resolver` returns `nil`, so the per-request scope equals
  `server.scope` and nothing observable changes for existing single-tenant
  servers.

### 4. Ownership enforcement (emergent — no new error, no per-op check)

The ETS stores already key by `{tenant, owner, id}` (`task_store/ets.ex:48`,
`push_config_store/ets.ex:49`). Once `scope.owner` carries a real value:

- `store.get(id, scope)` returns `:not_found` for a **different owner's** task,
  which `DefaultHandler` already maps to `A2A.Error{code: :task_not_found}`.
- This covers `GetTask`, `CancelTask`, `SubscribeToTask`, `send_message`
  follow-ups (a `taskId` owned by someone else is `TaskNotFound`, matching the
  existing "unknown id ⇒ TaskNotFound" rule), and all four push-config ops.
- `ListTasks` is filtered by scope via `:ets.match_object`, so it returns only
  the caller's tasks.

No `403`/forbidden is introduced: the A2A error table (spec §5.4) has none, and
returning one outside the set would be rejected by conformant clients. Making
another owner's task indistinguishable from a non-existent one is the
spec-faithful and non-leaking choice.

### 5. Authenticated extended card — `GetExtendedAgentCard`

- **JSON-RPC:** add `"GetExtendedAgentCard"` to `A2A.Plug.JSONRPC.@methods`,
  dispatched to a new `DefaultHandler.get_extended_agent_card(server, user)`.
- **REST:** add `GET /extendedAgentCard` to `A2A.Plug.Router` (per the vendored
  proto's `get: "/extendedAgentCard"` binding). This path is **not**
  agent-card-discovery — it is a normal operation, subject to identity resolution.
- **Behaviour** (`get_extended_agent_card/2`):
  1. If the base `agent_card`'s `capabilities.extended_agent_card` is not `true`,
     **or** `extended_agent_card_resolver` is `nil`, **or** the resolver returns
     `nil` → `{:error, %A2A.Error{code: :extended_agent_card_not_configured}}`.
  2. Otherwise return the resolved `AgentCard`, encoded via `A2A.JSON`.
- **No SDK-level auth rejection.** The resolver receives the (possibly anonymous)
  user and the host decides what — if anything — to reveal. An unauthenticated
  caller that the host wants to exclude is handled by the resolver returning
  `nil` ⇒ `:extended_agent_card_not_configured`.
- Rendered through the existing `A2A.Error.to_jsonrpc/1` / `to_rest/1`
  projections — the error already carries its `-32007` / `400` mapping.

### 6. Push outbound auth (verify + document; no new code)

`PushSender.Default.auth_headers/1` already:

- maps `AuthenticationInfo{scheme, credentials}` → `Authorization: "<scheme> <credentials>"`,
- maps a config `token` → `X-A2A-Notification-Token`,
- emits no auth header when neither is present.

This phase adds explicit unit tests for all three branches and documents the
behaviour in `cross-cutting.md`. JWT/JWKS signing remains a non-goal.

### 7. Documentation & ADR

- **New ADR** — *Identity, ownership scoping, and the authenticated extended
  card*: records the host-verifies/SDK-models boundary, the `owner_resolver` →
  `TaskNotFound`-on-mismatch decision (and why not a `403`), the resolver-based
  extended card, and the push-signing deferral.
- **`cross-cutting.md`** §Identity: mark landed; document `user_resolver`,
  `owner_resolver` (with the `TaskNotFound` semantics), and
  `extended_agent_card_resolver`; add the three config-table rows.
- **`scope-and-roadmap.md`**: move *Server-side auth/user model* from
  should-have to delivered; keep card-signing and (newly noted) push JWT/JWKS
  signing under deferred.
- **`CLAUDE.md`**: a sentence in the server-runtime paragraph noting the auth
  phase (identity, ownership scoping, extended card).

## Component boundaries

| Unit | Does | Depends on |
|---|---|---|
| `A2A.Plug.Identity` | Resolve `A2A.User` from conn, stash on `conn.private` | `server.user_resolver`, `A2A.User` |
| `A2A.Server` (struct/supervisor) | Hold the three hooks | — |
| `A2A.Plug.JSONRPC` / `A2A.Plug.REST` / `A2A.Plug.Router` | Carry `user` into dispatch; route `GetExtendedAgentCard` | `conn.private[:a2a_user]` |
| `A2A.Server.DefaultHandler` | Build per-request scope; set `RequestContext.user`; `get_extended_agent_card/2` | `owner_resolver`, `extended_agent_card_resolver`, stores |
| `A2A.Server.TaskStore` / `PushConfigStore` | Owner isolation (unchanged — already owner-keyed) | `A2A.Scope` |
| `A2A.Server.PushSender.Default` | Outbound auth headers (unchanged; now tested) | `AuthenticationInfo` |

## Testing (TDD — everyday `mix test`, no proto toolchain)

- **`A2A.Plug.Identity`**: default ⇒ anonymous; custom resolver populates
  `conn.private[:a2a_user]`; well-known path exempt.
- **Ownership isolation**: with an `owner_resolver` keyed on `user.id`, owner A
  cannot `GetTask` / `CancelTask` / `SubscribeToTask` / push-configure owner B's
  task (each ⇒ `TaskNotFound`); `ListTasks` returns only the caller's tasks;
  `send_message` continuation across owners is `TaskNotFound`. Default
  (`owner_resolver` returning `nil`) leaves single-tenant behaviour byte-for-byte
  unchanged.
- **`RequestContext.user`**: the executor observes the resolved user (not
  anonymous) when a resolver is configured.
- **Extended card**: (a) capability off ⇒ error; (b) no resolver ⇒ error;
  (c) resolver returns `nil` ⇒ error; (d) resolver returns a card ⇒ that card —
  on **both** JSON-RPC and REST.
- **Push auth headers**: scheme+credentials; token; neither.
- **Plug integration**: a resolver that reads a header (e.g. `x-user`) drives
  end-to-end ownership isolation over both bindings.

## Risks & constraints

- **Global-ETS limitation is unaffected.** Owner isolation is a *key prefix*
  within the single global table, not a second tree — the existing
  "two supervisors can't co-run" gotcha is orthogonal and unchanged. Tests vary
  ownership via the `owner_resolver` and request headers, not by starting a
  second server.
- **Every store call in `DefaultHandler` must switch** from `server.scope` to the
  per-request scope. Missing one would silently write/read under the wrong owner.
  The test matrix (both read and write paths, follow-up turns, push configs) is
  designed to catch an un-migrated call site.
- **Resolver totality**: a raising `user_resolver`/`owner_resolver` would crash
  the request. Documented as a host contract; the default resolvers are total.

## Rollout

Single feature branch `throng/AA-20`. Spec → draft PR → (on approval) plan →
subagent execution, pushing between plan tasks with `[no ci]`, final CI-triggering
commit, PR marked ready.
