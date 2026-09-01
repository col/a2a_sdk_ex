# 18. Identity resolution, ownership isolation, and the authenticated extended card

Date: 2026-09-01
Status: Accepted

## Context

[Cross-cutting §Identity & authentication](../cross-cutting.md#identity--authentication)
described the intended shape early — `A2A.User`, a `user_resolver` hook,
credential verification staying in the host's plug pipeline — but the runtime
wiring was not yet built: nothing resolved a caller before dispatch, nothing
scoped the `TaskStore`/`PushConfigStore` by owner, and `GetExtendedAgentCard`
had no server-side callback to reach.

The boundary the SDK draws stays fixed from that earlier design: **the host
verifies credentials, the SDK models the resulting identity and acts on it.**
Bearer tokens, JWT validation, session cookies — all of that is the host's own
plug pipeline. What the SDK owns is turning a verified request into an
`A2A.User`, deriving an ownership scope from it, and using both consistently
across every operation and both bindings.

Three call sites needed that identity, and needed it consistently:
`RequestContext.user` (so an executor can see its caller), the `TaskStore`/
`PushConfigStore` keys (so one tenant's tasks are invisible to another), and
`GetExtendedAgentCard` (a card variant gated on who's asking).

## Decision

**Resolve identity once, at the plug layer, before dispatch; fold it into a
per-request server handle; let storage keys and the extended-card resolver
consume it from there.**

- `A2A.Plug.Identity`, a router plug that runs before dispatch (exempting
  `/.well-known/…` agent-card discovery, which is unauthenticated by
  definition), calls the `user_resolver` server option — `(Plug.Conn.t() ->
  A2A.User.t())`, default an anonymous user — and stashes the result on
  `conn.private[:a2a_user]`.
- `A2A.Server.for_request/2` folds that resolved user together with an
  owner-scoped `A2A.Scope` (see below) into a per-request server handle; the
  router uses this handle for every operational route. `RequestContext.user`
  — previously hardcoded to an anonymous user — now carries the actual
  resolved caller.
- A second hook, `owner_resolver` — `(A2A.User.t() -> String.t() | nil)`,
  default `nil` — derives `A2A.Scope.owner`. The ETS `TaskStore` and
  `PushConfigStore` key entries by `{tenant, owner, id}`, so a caller whose
  resolved owner doesn't match a task's owner simply doesn't find it.
- **Cross-owner access returns `TaskNotFound`, not a 403/forbidden.** The A2A
  error table (spec §5.4) has no forbidden/permission-denied entry, and
  inventing a `reason` outside that set is worse than reusing one — a
  conformant client's error handling is built against the spec's fixed set,
  same reasoning [`cross-cutting.md` §Errors](../cross-cutting.md#errors)
  already applies to `:task_not_continuable` and `:task_in_progress`. It also
  costs nothing extra: `TaskNotFound` is exactly what a client without
  knowledge of the task's existence would see, so there's no information
  leak distinguishing "doesn't exist" from "exists, not yours."
- Default `owner_resolver` (`nil` for every user) collapses every task into
  one shared bucket — single-tenant, open-by-default behaviour is unchanged
  for hosts that configure nothing.
- `GetExtendedAgentCard` is served on both bindings (JSON-RPC method
  `GetExtendedAgentCard`; REST `GET /extendedAgentCard`), backed by a third
  hook, `extended_agent_card_resolver` — `(A2A.User.t() -> A2A.Types.AgentCard.t()
  | nil)`, default none configured. The operation is gated on all three:
  `capabilities.extended_agent_card == true` on the base card, a resolver
  configured, and that resolver returning a card for this caller — any miss
  falls through to the existing `:extended_agent_card_not_configured` error
  (`-32007` / `400 FAILED_PRECONDITION`). There is no SDK-level auth
  rejection of the request itself: the resolver receives the (possibly
  anonymous) `A2A.User` and decides what to return, including `nil` to signal
  "not for you."
- Push notification outbound auth — mapping a registered config's
  `AuthenticationInfo{scheme, credentials}` to an `Authorization` header and a
  `token` to `X-A2A-Notification-Token` — was already implemented in
  `PushSender.Default` and is now exercised by this phase's tests.
  **JWT/JWKS notification signing remains deferred**, the same class of work
  as the already-deferred agent-card signing (asymmetric crypto +
  canonicalization, not needed to host a functioning agent).

No new runtime dependency and no crypto were introduced by this phase.

## Consequences

- Identity and ownership are resolved exactly once per request, at the
  router boundary, rather than re-derived per operation — every handler call
  downstream (blocking, streaming, push CRUD) sees the same `A2A.User` and
  `A2A.Scope`.
- Defaults preserve prior behaviour completely: an unconfigured server has an
  anonymous `user_resolver`, a `nil` `owner_resolver` (one shared bucket, as
  before this phase), and no extended card resolver (existing
  `:extended_agent_card_not_configured` path, unchanged).
- Multi-tenant isolation is opt-in and additive: a host sets `owner_resolver`
  and gets `{tenant, owner, id}`-scoped storage with no other code change.
- The three resolvers are a host contract the SDK treats as total — a
  `user_resolver` that raises, or an `owner_resolver`/`extended_agent_card_resolver`
  that crashes on unexpected input, is a host bug, not something the SDK
  guards against beyond what `Execution`'s existing crash-to-`failed`
  handling already covers for executor code.
- `TaskNotFound`-for-cross-owner is a deliberate, permanent conflation with
  "doesn't exist" — a host that needs to distinguish the two for its own UI
  must do so outside the A2A error channel (e.g., its own authorization layer
  before requests even reach the SDK).
- JWT/JWKS push signing stays on the same deferred list as agent-card
  signing; both need real asymmetric crypto and neither blocks a host from
  running a fully functional, spec-conformant agent today.
