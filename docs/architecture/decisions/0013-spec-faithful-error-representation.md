# 13. Spec-faithful error representation on both bindings

Date: 2026-08-31
Status: Accepted

Supersedes, in part, [ADR-0011](0011-rest-binding-and-cancel-list.md) (REST
error body and content type).

## Context

[ADR-0011](0011-rest-binding-and-cancel-list.md) landed `A2A.Error.to_rest/1`
alongside `to_jsonrpc/1` as two projections of one table. The projections were
right in structure and wrong in detail: measured against the official TCK, four
MUST-level requirements failed on how errors are *represented*, not on which
errors are raised.

- `JSONRPC-ERR-003` — "error.data must be an array, got dict". §9.5 requires
  the `google.rpc.ErrorInfo` to sit **in an array** at `error.data`; we put the
  error's `data` map there raw.
- `HTTP_JSON-ERR-002` — "Response is not AIP-193 format". §11.6 requires the
  AIP-193 envelope `{"error": {code, status, message, details}}`; we emitted a
  bare `google.rpc.Status` (no wrapper, and `code` a `google.rpc.Code` int
  rather than the HTTP status).
- `HTTP_JSON-ERR-001` and `HTTP_JSON-SVC-001` — "Content-Type must be
  application/json"; we sent `application/a2a+json` on every REST response.

Three rows of the §5.4 table were also simply wrong (`TaskNotCancelable` 400
rather than 409, `ContentTypeNotSupported` 400 rather than 415,
`InvalidAgentResponse` 500 rather than 502), and three spec errors had no row at
all (`-32007`, `-32008`, `-32009`).

## Decision

**The table is §5.4 verbatim, and carries the gRPC status *name*.** AIP-193
needs `status` as a string (`"NOT_FOUND"`), so the column that held a canonical
`google.rpc.Code` int now holds the name. The int had exactly one consumer —
the REST body's `code` — and that field is now the HTTP status instead, so
nothing lost a reader.

**Errors with no spec reason carry no ErrorInfo.** `reason` is `nil` for the
standard JSON-RPC errors (`invalid_params`, `internal_error`, `timeout`), and
both renderers omit the ErrorInfo for them. The spec mandates ErrorInfo "for
A2A-specific errors" only, and a conformant client rejects a `reason` outside
the spec's set — so emitting `INVALID_ARGUMENT` as a reason, as we did, was
worse than emitting nothing.

**The SDK's three invented codes get spec homes rather than invented reasons.**
`:task_not_continuable` and `:task_in_progress` render as
`UnsupportedOperation` (`-32004`/400): §3.4 and §3.6 name that error for
messages sent to, and subscribes on, a task in a terminal state, and "this
server won't accept a second message while the first executes" is the same
class of refusal. `:timeout` renders as an internal error. Their previous
reasons (`TASK_NOT_CONTINUABLE`, `TASK_IN_PROGRESS`) were not in the spec's set
and would have been rejected wherever they surfaced.

**REST uses `application/json`.** The spec contradicts itself here: §6's
examples and the §14.1.1 IANA registration say `application/a2a+json`, while
§11.1 — the normative binding section — says "`application/json` for requests
and responses". We follow §11.1, on both success and error responses. The
registered media type is not a superset for matching purposes: a client testing
for the `application/json` subtype never matches `application/a2a+json`.
Push-notification delivery (`A2A.Server.PushSender.Default`) keeps
`application/a2a+json`; it is not the REST binding.

**A decode failure renders through `to_rest/1` like any other error.**
`A2A.Plug.REST` had a hand-built `bad_request/1` body, which is precisely how
two projections of one table drift back apart. It now builds an
`%A2A.Error{code: :invalid_params}` and renders it.

## Consequences

The wire form changes for every REST error and for JSON-RPC A2A errors. This is
a breaking change for any client that parsed the old shapes, taken knowingly
before 1.0: the old shapes were not the shapes the spec describes, so no
conformant client depended on them.

`error.data` is now heterogeneous by design — an array for A2A errors, a plain
object for standard ones. That mirrors §9.5, whose own examples show both, but
it means a client must type-check before indexing.

ErrorInfo `metadata` keys are camelCased (§5.5), so `%{task_id: "t"}` renders as
`{"taskId": "t"}`, matching the §11.6 example.

Four MUST requirements move to passing. The remaining error-shaped TCK failures
are about *raising* the right error, not representing it — rejecting an
unsupported `A2A-Version` (`-32009`/400), rejecting an unacceptable request
`Content-Type` (`-32005`/415), `TaskNotFound` for an unknown `taskId` on
follow-up messages, and `UnsupportedOperation` for a subscribe on a terminal
task. All four now have correct rows waiting for them; each needs detection
logic in the transport or handler, which is a separate change.
