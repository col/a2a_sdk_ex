# Ergonomic agent runtime — `A2A.Server.Agent`

Status: approved (brainstorm 2026-09-01)
Branch: `throng/AA-19`

## Purpose

Today an agent author writes a module that implements the
`A2A.Server.AgentExecutor` behaviour, defines `execute/2`, and **imperatively**
drives a `TaskUpdater` (`start_work |> add_artifact |> complete`). That low-level
seam is the right primitive — it mirrors the official Python/JS SDKs' executor
and gives full control over event ordering, chunking, and cancellation — but it
is more ceremony than a simple agent needs.

This spec adds a **runtime-style** ergonomic layer over that primitive: a
`use A2A.Server.Agent` macro whose single `handle_message/1` callback returns a
declarative value describing the reply, letting a trivial agent skip the
imperative `TaskUpdater` dance entirely. It is added **without** removing or
weakening the low-level executor — a declarative DSL over a purely additive
macro.

The design goal is **best-of-both-worlds**: a five-line agent is possible, a
richly-structured agent (named + metadata'd artifacts, streamed output,
multi-turn) is expressible in the same declarative vocabulary, and anyone who
needs raw imperative control simply keeps using `A2A.Server.AgentExecutor`
directly — the two layers coexist.

No new runtime dependencies. The macro compiles to an `AgentExecutor`; the DSL
result is interpreted through the existing `TaskUpdater`.

## Design principles

1. **Additive, never a replacement.** `use A2A.Server.Agent` *generates* an
   `A2A.Server.AgentExecutor` (`execute/2`, `cancel/2`). The behaviour, the
   `TaskUpdater`, and the whole server runtime are untouched. The escape hatch
   for raw control is "don't use the macro" — implement the behaviour directly,
   exactly as today.
2. **One DSL, no tuple sugar.** The author returns a single declarative value —
   an `%A2A.Server.Agent.Result{}` built with a small pipeable API. We
   deliberately do **not** also offer `{:reply, parts}` tuple shortcuts; one
   representation keeps the surface, the docs, and the tests singular.
3. **Pure data, interpreted once.** `Result` is a side-effect-free value that
   accumulates *directives*. The runtime folds it into `TaskUpdater` calls at the
   end of `handle_message/1`. This makes agent logic unit-testable without
   standing up a server, and it is the seam that makes streaming (a lazily-held
   `Enumerable`) fit a "batch" return value.
4. **Protocol-faithful.** The interpreter enforces the invariants the protocol
   (and `A2A.Server.ResultAssembler`) already imposes: artifacts flush **before**
   the terminal; exactly **one** terminal per result; streamed artifacts use
   append/`last_chunk` chunk-merge semantics. Streaming is **artifacts only** —
   status messages have no merge semantics in the assembler, so there is no
   "streamed message".

## Scope

### In

- **`A2A.Server.Agent.Result`** — the pure result value + pipeable builder
  (`reply/0`, `artifact/4`, `stream/4`, `message/2`, `complete/1`,
  `input_required/1`, `reject/2`, `fail/2`). Includes the `Enumerable`-carrying
  stream directive.
- **`A2A.Server.Agent.Interpreter`** — folds a `Result` into `TaskUpdater` calls
  in directive order, enforcing the ordering/terminal invariants.
- **`A2A.Server.Agent`** — the `use`-able macro. Injects a generated
  `A2A.Server.AgentExecutor` implementation (`execute/2` calls the author's
  `handle_message/1`, runs the interpreter; `cancel/2` default emits `:canceled`,
  overridable). Injects agent-card generation (`agent_card/1` + `skills/1`
  overridable callbacks) from `use` options. Declares the `handle_message/1`
  callback.
- **Serve-time agent-card `url` resolution** — `A2A.Plug.Router` (and the REST
  card route, if separate) resolve the card's `url` at request time from `conn`
  when the stored card's `url` is `nil`; a non-nil `url` (author-pinned) is used
  verbatim. Small, shared helper.
- **Docs + example** — module docs with the canonical examples; rewrite
  `examples/echo_server` to `use A2A.Server.Agent` as the "how do I write an
  agent" reference. An ADR recording the additive-macro decision.

### Out (non-goals)

- **`progress/2`** (discrete intermediate `:working` status pings). Deferred —
  additive, lands later without touching this design. Noted as a future
  extension only.
- **Tuple-return sugar.** Explicitly rejected (principle 2).
- **Wiring sugar** (auto `child_spec`, hiding `Supervisor`/`Standalone`). Out of
  scope — the SDK deliberately exposes the OTP wiring, and multiple servers need
  distinct names. Authors still start `A2A.Server.Supervisor` themselves.
- **`X-Forwarded-*` proxy header support** for URL resolution. The author pins a
  canonical `url` for proxied deployments; honoring forwarded headers is a
  possible later addition.
- **Client**, telemetry, registry/fleet layers — separate future work, not part
  of this spec.

## Author-facing surface

### The macro

```elixir
defmodule MyAgent do
  use A2A.Server.Agent,
    name: "my-agent",
    description: "Does things",
    version: "1.0.0",
    skills: [%{id: "echo", name: "Echo", description: "Echoes input"}]

  @impl A2A.Server.Agent
  def handle_message(ctx) do
    reply()
    |> artifact("answer", "echo: " <> A2A.Server.RequestContext.user_input(ctx))
  end
end
```

No `complete()` — **the terminal is optional; a `Result` with no explicit
terminal completes.** An author only names a terminal to pick a *non*-completed
outcome (`input_required`/`reject`/`fail`) or to attach a completion
message/metadata. This is the simple-case ergonomic win: declare your artifacts,
done.

- **Required callback:** `handle_message(RequestContext.t()) :: Result.t()`.
  Everything needed for multi-turn is on `ctx` — `ctx.message`, `ctx.task` (set
  on resumption), `ctx.user`, `ctx.config`, `ctx.metadata`. No second argument.
- **`use` imports** the `Result` builder functions so the DSL reads cleanly in
  the callback body.

### The `Result` DSL

`import`ed into the agent module by `use`. Every function takes and returns a
`%Result{}` (except `reply/0` which seeds one), so they pipe.

| Function | Purpose | → `TaskUpdater` |
| --- | --- | --- |
| `reply()` | Seed an empty result. | — |
| `artifact(r, name, parts, opts \\ [])` | Buffered artifact. `parts` = string \| `%Part{}` \| list; `opts`: `id`, `metadata`. | `add_artifact/3` (emitted in order, before terminal) |
| `stream(r, name, enumerable, opts \\ [])` | One artifact delivered in chunks. Each element = string \| `%Part{}`. `opts`: `id`, `metadata`. | fold → `add_artifact/3` with `append: true`, `last_chunk: true` on final element |
| `message(r, parts, opts \\ [])` | Set the terminal status message. `opts`: `metadata`. | carried onto the terminal status |
| `complete(r, opts \\ [])` | **Optional** terminal `:completed`. `opts`: `message`, `metadata`. Omitting any terminal completes with the same defaults. | `complete/…` |
| `input_required(r, opts \\ [])` | Terminal-for-drain `:input_required` (task stays resumable). | `requires_input/…` |
| `reject(r, reason \\ nil)` | Terminal `:rejected`. | `reject/…` |
| `fail(r, reason)` | Terminal `:failed`. | `fail/…` |

`name` is the artifact name (`nil` allowed for anonymous). `id` defaults to a
freshly generated id per directive. Note the interpreter emits buffered
`artifact/4` directives with `append: false`, so two directives sharing an `id`
**replace** (per `ResultAssembler.merge_artifact/3`), not append — incremental
append is `stream/4`'s job, not a buffered-artifact idiom.

**String sugar** is uniform: anywhere `parts` is accepted, a bare `String.t()`
means `A2A.Types.Part.text/1`, and a list mixes strings and `%Part{}`.

### Examples

Rich, multi-artifact with metadata:

```elixir
def handle_message(_ctx) do
  reply()
  |> artifact("report", Part.raw(pdf, filename: "report.pdf"), metadata: %{"pages" => 12})
  |> artifact("summary", "TL;DR: all green", id: "sum-1")
  |> complete(message: "2 artifacts generated", metadata: %{"model" => "opus-4.8"})
end
```

Streaming, composed with a buffered artifact:

```elixir
def handle_message(msg) do
  reply()
  |> artifact("prompt-echo", user_text(msg))   # buffered, emitted first
  |> stream("answer", token_stream(msg))       # incremental chunks
  |> complete(metadata: %{"tokens" => 128})    # terminal after stream drains
end
```

Multi-turn / terminal variants:

```elixir
reply() |> message("What's the target currency?") |> input_required()
reply() |> reject("unsupported region")
reply() |> fail("upstream timeout")
```

## Architecture

### Result value

```elixir
defmodule A2A.Server.Agent.Result do
  @type directive ::
          {:artifact, name :: String.t() | nil, parts :: [Part.t()], opts :: keyword()}
          | {:stream, name :: String.t() | nil, Enumerable.t(), opts :: keyword()}
  @type terminal ::
          {:completed, keyword()} | {:input_required, keyword()}
          | {:rejected, keyword()} | {:failed, keyword()}

  @type t :: %__MODULE__{
          directives: [directive()],   # accumulated in author order (reverse-built, reversed on read)
          message: {[Part.t()], keyword()} | nil,
          terminal: terminal() | nil
        }
end
```

- Builder functions append directives / set `message` / set `terminal`.
- Setting a second terminal **raises** at build time with a clear message
  (`ArgumentError`) — the pipe already has all it needs to detect it.
- `parts` normalization (string → `Part.text/1`, single → list) happens in the
  builder so the interpreter sees only `[Part.t()]`.
- `Result` is pure: no store, no pubsub, no ids-with-side-effects (artifact ids
  default lazily in the interpreter, or are captured from `opts`).

### Interpreter

```elixir
A2A.Server.Agent.Interpreter.run(%Result{} = result, %TaskUpdater{} = updater) :: :ok
```

Fold, in order:

1. `TaskUpdater.start_work/1` once, up front (the runtime always signals working
   before output — matches current authored executors).
2. Each directive → `add_artifact/3`. `:stream` enumerates the `Enumerable`
   inside the current (execution-child) process, emitting one appended chunk per
   element under a shared `artifact_id`, `last_chunk: true` on the final element.
   An empty stream emits a single empty `last_chunk` artifact (well-defined).
3. Terminal → the matching `TaskUpdater` call, threading `message` + `metadata`.
   **The terminal is optional: a `Result` with no terminal set completes**
   (`TaskUpdater.complete/1` with default message/metadata). A `handle_message`
   that returns `reply()` with only artifacts — or even a bare `reply()` — is a
   completed task. An explicit terminal is only needed to select a
   non-completed outcome or to attach completion message/metadata.

Invariants enforced here (belt-and-braces with `ResultAssembler`): artifacts
before terminal (structural — terminal is applied last), exactly one terminal
(guarded at build time), streamed chunks share one id.

**Error semantics.** `handle_message/1` raising, or a stream element raising
mid-enumeration, surfaces exactly as today: the exception propagates out of
`execute/2`, the execution child exits non-normally, and
`A2A.Server.Execution` fails the task once via its `:DOWN` path. The interpreter
adds no new rescue. (If a partial stream already emitted chunks, those events
stand and the task then fails — same as a hand-written executor that raises
mid-stream.)

### The generated executor

`use A2A.Server.Agent` injects:

```elixir
@behaviour A2A.Server.AgentExecutor

@impl true
def execute(ctx, updater) do
  ctx |> handle_message() |> A2A.Server.Agent.Interpreter.run(updater)
  :ok
end

@impl true
def cancel(_ctx, updater) do
  A2A.Server.TaskUpdater.update_status(updater, :canceled)
  :ok
end

defoverridable cancel: 2
```

- `cancel/2` gets a sensible default (emit `:canceled`) and is `defoverridable`
  so an author can run compensating logic. This matches
  `A2A.Server.Execution.maybe_author_cancel/2`, which already calls
  `executor.cancel/2` when exported.
- `handle_message/1` is the sole required callback (`@callback`, enforced by the
  behaviour the macro declares).

### Agent-card generation

`use` options populate a default `%A2A.Types.AgentCard{}` with **sensible
defaults** for anything omitted:

- Directly mapped: `name`, `description`, `version`, `default_input_modes`,
  `default_output_modes`, `provider`, `security_schemes`, … (allow **every**
  card field as a `use` option).
- `capabilities`: auto-derived where unambiguous — `streaming: true` (the runtime
  always supports it); `push_notifications` left to the host to advertise
  (defaults to the card's own default, overridable via option).
- `url`: left `nil` by default — resolved at serve time (below). An author may
  pin a canonical `url` via option.

Two overridable callbacks, invoked **in this order** at card-build time:

1. `skills(default_skills) :: [AgentSkill.t()]` — receives the skills built from
   the `skills:` option (lightweight maps → `%A2A.Types.AgentSkill{}`), returns
   the final skill list. Lets an author compute skills dynamically.
2. `agent_card(default_card) :: AgentCard.t()` — receives the fully-built default
   card (**including** the resolved skills from step 1) and returns the final
   card. Best-of-both-worlds: keep the generated defaults, tweak what you want.

Both are `defoverridable`; default `skills/1` and `agent_card/1` are identity
functions over their argument. The macro exposes the composed result as a
zero-arg `agent_card/0` (the template card) that slots into
`A2A.Server.Supervisor`'s `agent_card:` option:

```elixir
{A2A.Server.Supervisor, name: MyAgent.Server, executor: MyAgent,
 pubsub: MyApp.PubSub, agent_card: MyAgent.agent_card()}
```

Lightweight skill maps accept `%{id:, name:, description:, tags:, examples:, …}`
and are validated for required fields (`id`, `name`) at build time.

### Serve-time `url` resolution

The stored card is a **template**; its `url` may be `nil`. A shared helper
resolves the effective `url` when serving `/.well-known/agent-card.json`:

```elixir
A2A.Server.AgentCardURL.resolve(card, conn) ::
  # card.url when non-nil (author pinned a canonical/base URL) — used verbatim;
  # otherwise derived from conn: "#{scheme}://#{host}[:#{port}]" <> mount_path
```

- **Mount path** from `conn.script_name` (the segments the host router consumed
  before forwarding), so a mounted `A2A.Plug.Router` reports the correct absolute
  URL. Standalone `script_name` is empty → root.
- **Port** omitted when default for the scheme (80/http, 443/https).
- `A2A.Plug.Router`'s existing `get "/.well-known/agent-card.json"` clause calls
  the helper before encoding; the REST card path (if distinct) shares it.
- This makes **both** deployment cases correct for the common (no-proxy) case
  with zero config; proxied deployments pin `url` explicitly.

## Data flow

```
HTTP → A2A.Plug.* → DefaultHandler → A2A.Server.Execution
                                        └─ child process runs execute/2:
                                             handle_message(ctx) → %Result{}
                                             Interpreter.run(result, updater)
                                               → TaskUpdater.start_work
                                               → add_artifact … (incl. stream folds)
                                               → complete | requires_input | reject | fail
                                                   → ResultAssembler + store + PubSub broadcast
GET /.well-known/agent-card.json → AgentCardURL.resolve(template_card, conn) → JSON
```

Nothing in the event/streaming/push path changes: the interpreter emits the same
domain events a hand-written executor emits, so SSE, resubscribe, and push
delivery see identical `TaskStatusUpdateEvent` / `TaskArtifactUpdateEvent`
frames whether the author used the macro or the raw behaviour.

## Testing strategy (TDD)

- **`Result` builder (pure, no server):** each function accumulates the right
  directive; string/list normalization; second-terminal raises; default terminal
  is `:completed`.
- **`Interpreter` (against a `TaskUpdater` over an in-test store/pubsub):**
  directive order preserved; artifacts precede terminal; `stream/4` produces
  append chunks sharing one id with `last_chunk` only on the last; empty stream
  well-defined; each terminal maps to the right `TaskUpdater` call with
  message/metadata threaded; a raising stream element propagates (task fails via
  the existing `Execution` path — asserted at the executor/integration level).
- **Macro:** generated module satisfies `A2A.Server.AgentExecutor` (both
  callbacks exported); `handle_message/1` required; `cancel/2` default emits
  `:canceled` and is overridable.
- **Agent card:** defaults filled; `skills/1` runs before `agent_card/1` and its
  output is present in the card passed to `agent_card/1`; overrides compose;
  lightweight skill maps validated.
- **Serve-time URL:** pinned `url` used verbatim; `nil` derives from `conn`
  (standalone root; mounted honors `script_name`; default ports omitted). Router
  integration test through `A2A.Plug.Router`.
- **End-to-end:** the rewritten `examples/echo_server` (or an SDK integration
  test) drives `SendMessage` and `SendStreamingMessage` through the macro agent
  over both bindings, asserting identical event frames to the current
  hand-written executor.

## Module inventory

| Module | New/changed | Responsibility |
| --- | --- | --- |
| `A2A.Server.Agent` | new | `use` macro: generated executor, card callbacks, DSL import |
| `A2A.Server.Agent.Result` | new | pure result value + pipeable builder |
| `A2A.Server.Agent.Interpreter` | new | fold `Result` → `TaskUpdater` |
| `A2A.Server.AgentCardURL` | new | serve-time `url` resolution from `conn` |
| `A2A.Plug.Router` | changed | call `AgentCardURL.resolve/2` on card route |
| `A2A.Plug.REST` | maybe changed | share URL resolution if it serves the card |
| `examples/echo_server` | changed | rewritten onto `use A2A.Server.Agent` |
| `docs/architecture/decisions/0013-ergonomic-agent-macro.md` | new | ADR |

## Open questions / risks

- **`script_name` fidelity behind nested forwards.** `conn.script_name` is
  correct for a single `forward`; deeply nested/custom mounts could differ. The
  pinned-`url` override is the escape hatch; documented.
- **Terminal-less completes (decided).** A terminal-less `Result` completes
  rather than raising — a deliberate ergonomic choice so the simplest agents
  ("declare artifacts, done", or even a bare `reply()`) need no terminal. The
  cost is that a genuinely-forgotten terminal silently completes instead of
  erroring; accepted, since "no terminal ⇒ completed" is the intuitive default
  and the build-time guard still catches the opposite mistake (two terminals).
```
