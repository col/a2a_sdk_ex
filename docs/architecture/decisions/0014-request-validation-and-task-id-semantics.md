# 14. Request validation: service parameters and task-identifier semantics

Date: 2026-08-31
Status: Accepted

## Context

[ADR-0013](0013-spec-faithful-error-representation.md) made the error *table*
spec-faithful and left rows that nothing could reach: `VersionNotSupported`,
`ContentTypeNotSupported`, and — for the operations below — `TaskNotFound` and
`UnsupportedOperation`. Four MUST-level TCK requirements failed not on how an
error is rendered but on the server failing to raise one at all.

- `VER-SERVER-002` — an `A2A-Version: 99.0` request was processed normally. §6.3
  requires the agent to process a request under the requested version's
  semantics and to return `VersionNotSupportedError` when it cannot.
- `JSONRPC-SSE-002` / `HTTP_JSON-STATUS-001` — a request with
  `Content-Type: text/plain` reached the JSON parser and came back as
  `ParseError`, where §11.1 wants `ContentTypeNotSupportedError`.
- `CORE-MULTI-004` — a `Message` naming a `taskId` that does not exist created a
  task under that id. §3.4.2 is explicit: "Client-provided `taskId` values for
  creating new tasks is **NOT** supported", and agents "**MUST** return a
  `TaskNotFoundError` if the provided `taskId` does not correspond to an
  existing task".
- `STREAM-SUB-003` — `SubscribeToTask` on a terminal task returned a
  snapshot-only stream. §3.1.6 says it "returns `UnsupportedOperationError` if
  the task is in a terminal state".

## Decision

**Service parameters are validated once, before dispatch.** `A2A.Plug.ServiceParams`
holds the checks; `A2A.Plug.Router` runs it as a plug between `:match` and
`:dispatch`, so both bindings refuse the same requests and each renders the
refusal in its own shape — a JSON-RPC error envelope (HTTP 200, null id, since
the envelope has not been parsed and there is no request id to echo) or the
AIP-193 body with its status.

**The checks are lenient about absence and strict about disagreement.** A client
that states no version or no media type is taken to mean the ones this SDK
implements; only a value that actively conflicts is refused. Three consequences
worth naming:

- An **empty** `A2A-Version` counts as unstated. §6.3 says 0.3 is assumed for an
  empty header, and we do not implement 0.3 — but rejecting a header a client
  merely left blank is hostile, and the TCK's `VER-SERVER-003` expects such a
  request to succeed.
- Versions match on `Major.Minor` per §6.3, so `1.0.7` is `1.0`.
- The version is also read from an `A2A-Version` **query parameter**, which §6.3
  permits as an alternative to the header. Reading only the header would let
  `?A2A-Version=99.0` through.

`application/a2a+json` and any other `+json` structured suffix are accepted on
requests even though ADR-0013 stopped emitting them: what we send and what we
must tolerate are different questions.

**Agent-card discovery is exempt from version gating.** A client reads the card
to learn which versions an agent speaks; gating the card on the version would be
circular.

**Task ids are server-generated, full stop.** `A2A.Server.DefaultHandler`'s
`reject_terminal/2` became `resolve_task/2`: an absent `taskId` means "create",
and a supplied one must reference an existing, non-terminal task. An unknown id
is `TaskNotFound`, not an implicit create.

**`SubscribeToTask` on a terminal task is an error, not an empty stream.** A
snapshot-only stream is not a substitute: a subscriber cannot distinguish it
from a task that is merely quiet.

## Consequences

The task-id change is the disruptive one. Callers that supplied their own
`taskId` to *create* a task now get `TaskNotFound`, and this SDK's own test
suite was doing exactly that — a dozen tests pinned an id that way. They now
pin `server.id_generator` instead, which is the honest way to get a predictable
id in a test and does not depend on a client capability the spec denies.

Validating before dispatch means a bad service parameter is refused even on a
path that would otherwise 404. That is defensible (both are refusals) and keeps
the check in one place rather than scattered across ten routes.

`ServiceParams.protocol_version/0` is now the single place the supported
version is stated. It is deliberately *not* read from the configured
`AgentCard`: the card advertises a version per interface and may be absent
entirely, while the check needs one answer that always exists.

Six requirements move to passing (`VER-SERVER-002`, `VER-SERVER-003`,
`JSONRPC-SSE-002`, `HTTP_JSON-STATUS-001`, `CORE-MULTI-004`, `STREAM-SUB-003`).
`STREAM-SUB-002` still fails, for a reason outside this change: it drives a
task to completion by sending a *follow-up* message on an existing task, which
needs real multi-turn continuation — the same gap the `CORE-HIST-*` failures
describe, where an incoming user message never reaches the task's history.
