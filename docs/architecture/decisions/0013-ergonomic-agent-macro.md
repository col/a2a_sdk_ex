# 13. Ergonomic agent runtime macro (`A2A.Server.Agent`)

Date: 2026-09-01
Status: Accepted

## Context

`A2A.Server.AgentExecutor` — a two-callback behaviour (`execute/2`, `cancel/2`)
that receives a `RequestContext` and an imperative `TaskUpdater` handle — is
the correct low-level seam: it is exactly what `A2A.Server.Execution` needs to
run an author's agent in its own supervised, monitored child process (ADR-0011),
and it makes no assumption about how an author wants to structure their logic.

But it is verbose for the overwhelmingly common case: an agent that takes the
caller's input, does some work, and emits one or a few artifacts before
settling into a terminal status. That shape requires an author to hand-drive
`TaskUpdater.start_work/1`, build `Artifact`/`Part`/`Message` structs
directly, get streaming chunk-append semantics (`append`/`last_chunk`) right,
and remember to call `update_status/3` exactly once. It also duplicates the
`AgentCard` an author must hand-assemble separately (as `examples/echo_server`
did, pre this ADR, via a free-standing `EchoServer.AgentCard.card/1`) and,
before ADR-0012's URL-resolution follow-on, forced the card's
`supported_interfaces[].url` to be a hardcoded constant baked in at
supervision-tree start rather than derived from the inbound request.

The goal: give the common case a small, pure DSL and a card built from `use`
options, without touching or gating `AgentExecutor` — the transport, process,
and PubSub layers underneath it are unaffected and this must stay optional.

## Decision

**An additive `use A2A.Server.Agent` runtime, generating an `AgentExecutor`.**
`use A2A.Server.Agent, name: ..., description: ..., ...` expands to a module
that `@behaviour A2A.Server.AgentExecutor`s and `@behaviour A2A.Server.Agent`s.
The generated `execute/2` calls the author's required `handle_message/1`
callback and folds the `A2A.Server.Agent.Result` it returns through
`A2A.Server.Agent.Interpreter.run/2`; the generated `cancel/2` defaults to
`TaskUpdater.update_status(updater, :canceled)` and is `defoverridable`. Both
callbacks still run inside `Execution`'s monitored child process exactly as a
hand-written `AgentExecutor` would — the macro changes nothing about the
process model, only what an author writes inside it.

**A pure `Result` DSL — single form, no tuple sugar.** `A2A.Server.Agent.Result`
is a plain struct (`directives`, `message`, `terminal`) built by piping:
`reply()` (the accumulator seed) through `artifact/4`, `stream/4`, `message/3`,
and exactly one terminal (`complete/2`, `input_required/2`, `reject/2`,
`fail/2`). It performs no side effects and touches no process state — every
function is `Result.t() -> Result.t()`, so `handle_message/1` is a plain,
testable, referentially-transparent function. A second terminal call raises
(`ArgumentError`, "terminal already set") rather than silently overwriting,
because two terminal statuses on one task is always an authoring bug, not a
valid intent to disambiguate. Text/`Part`/list-of-either are all accepted
directly (no `{:text, ...}` tuple sugar) — `Result.normalize_parts/1` wraps
bare strings as `Part.text/1` so the common one-line artifact reads as prose,
not as protocol plumbing.

**Streaming is artifacts-only.** `stream/4` takes any `Enumerable.t()` and the
`Interpreter` chunk-merges it into `TaskUpdater.add_artifact/3` calls with
`append: true`, marking `last_chunk: true` only on the final element (a
one-behind buffer, not eager chunk-per-element, so the last chunk's
`last_chunk` flag is set correctly without look-ahead into the caller's
enumerable). There is no analogous "streaming status/message" primitive —
`TaskStatus` updates are inherently point-in-time, not a chunked sequence, so
extending the streaming primitive there would be modeling something the
underlying types don't represent. An author who needs to emit incremental
status updates already has that as a plain `AgentExecutor`.

**The terminal is optional; omitting it still completes.** `Interpreter.run/2`
defaults `result.terminal` to `{:completed, []}` when the author's
`handle_message/1` never calls a terminal function — matching the intuition
that "an agent that produced output and didn't fail, reject, or ask a
question" succeeded. This makes the minimal agent
(`reply() |> artifact(...)`, as `EchoServer.Agent` now is) a single
expression with no explicit `complete()` needed.

**Card sugar layered on the same `use` options, with two overridable
seams.** `A2A.Server.Agent.build_card/2` derives an `AgentCard` from the `use`
opts (defaulting `default_input_modes`/`default_output_modes` to
`["text/plain"]`, `capabilities` to `%AgentCapabilities{streaming: true}`, and
`supported_interfaces` to the standard JSONRPC + HTTP+JSON pair with `url:
nil` — left for ADR-0012's `AgentCardURL.resolve/2` to fill at serve time).
Skills accept lightweight maps (`%{id:, name:, description:, tags:}`) as well
as full `AgentSkill` structs, converted by `build_skill/1`, so the common case
never touches the typed struct directly. Two `defoverridable` callbacks let an
author customize without re-deriving everything: `skills/1` (default
identity) runs first and can post-process the map-built skill list;
`agent_card/1` (default identity) runs last and can adjust or replace any
field of the fully-built card. The generated `agent_card/0` (no `use`
options's `agent_card/1` is a *callback* on the built card, distinct from
this zero-arity accessor) is what a host calls at supervision-tree start —
`EchoServer.Agent.agent_card()` — same shape any hand-built `AgentCard` would
be passed to `A2A.Server.Supervisor`.

**No wiring sugar, no `progress/2`.** The macro does not generate
supervision-tree children, router mounting, or anything past the
`AgentExecutor`/`AgentCard` seam — a host still assembles
`A2A.Server.Supervisor` + `A2A.Standalone`/host router exactly as before,
just passing `EchoServer.Agent` and `EchoServer.Agent.agent_card()` instead of
hand-written equivalents. There is deliberately no incremental
"progress" primitive distinct from `stream/4` — one mechanism for
incremental output, not two with overlapping semantics.

**`examples/echo_server` is the reference usage.** `EchoServer.Agent` replaces
both `EchoServer.Executor` and `EchoServer.AgentCard` with a single ~20-line
module; `EchoServer.Application` drops the hardcoded `base_url` string
entirely — `agent_card: EchoServer.Agent.agent_card()` builds a card with
`url: nil` interfaces, and `A2A.Plug.Router`'s existing `AgentCardURL.resolve/2`
call (ADR-0012) fills them from each request's actual scheme/host/port/mount
path.

## Consequences

- Two coexisting layers: `A2A.Server.AgentExecutor` (imperative, full control)
  and `A2A.Server.Agent` (declarative DSL, common case). Neither depends on
  the other existing; an author picks per-agent, and nothing in `Execution`,
  `TaskStore`, transports, or push notifications needed to change to support
  this — the macro's `execute/2`/`cancel/2` are ordinary `AgentExecutor`
  callbacks from every other layer's point of view.
- **The escape hatch is "don't use the macro."** Any agent that needs
  behavior the `Result`/`Interpreter` pair doesn't model (per-status-update
  streaming, custom cancellation beyond marking `:canceled`, artifacts built
  outside the `TaskUpdater` calling convention the `Interpreter` assumes)
  implements `A2A.Server.AgentExecutor` directly — same as before this ADR,
  no new constraint introduced.
- No new dependencies — `A2A.Server.Agent`, `Result`, and `Interpreter` are
  pure Elixir over the existing `A2A.Server.TaskUpdater`/`A2A.Types.*` surface.
- `examples/echo_server` shrinks from three modules
  (`Executor` + `AgentCard` + `Application`) to two (`Agent` + `Application`),
  and its application no longer needs to know its own externally-visible
  `base_url` — a small but real correctness improvement, since a hardcoded
  `localhost:5001` was already wrong for the agent running behind any proxy
  or port mapping.
- **Deferred, additive behind these seams:** a `progress/2`-style incremental
  status primitive, tuple-based directive sugar (`{:text, ...}` etc.), and any
  supervision-tree/router wiring sugar remain explicit non-goals for now — the
  DSL stays to output shaping, not process assembly.
