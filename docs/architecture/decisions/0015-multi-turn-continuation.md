# 15. Multi-turn continuation: seeded executions and exchange history

Date: 2026-08-31
Status: Accepted

## Context

[ADR-0014](0014-request-validation-and-task-id-semantics.md) made a `Message`
carrying an existing `taskId` reference a real task rather than create one. What
it did *not* do is make the second turn continue the first. Four
requirements failed on the consequences, and they turned out to be four
independent gaps rather than one:

1. **A follow-up started a blank task.** `Execution.init/1` always seeded
   `TaskUpdater` with `ResultAssembler.init/2` — a fresh `%Task{}` at
   `:submitted`. Turn two silently discarded turn one's history and artifacts.
   `TaskUpdater.new/3` already accepted a `task:` option; nothing passed one.
2. **Incoming user messages never entered history.** `ResultAssembler.apply/2`
   has had a `%Message{}` clause appending to history since the walking
   skeleton; nothing ever fed it one. Only agent status-messages were recorded,
   so history read `['Hello from TCK']` however long the exchange.
3. **`historyLength` was honoured on `ListTasks` alone.** `truncate_history/2`
   existed and was called from one place. `GetTask` and `SendMessage` ignored it.
4. **A settled non-terminal task's subscribe stream closes immediately** —
   `STREAM-SUB-002`. Left out of this change deliberately; see below.

## Decision

**A turn is seeded, not started from nothing.** `DefaultHandler` resolves the
stored task once (`resolve_task/2`, which already had to read it to reject
unknown ids), appends the incoming message to it, and passes the result as the
execution's starting projection. `resolve_task/2` therefore returns `{:ok,
task_or_nil}` rather than `:ok` — the read it was already doing now feeds the
continuation instead of being discarded.

The **blocking drain is seeded from the same value.** It folds events into its
own projection, separate from the updater's, so leaving it on
`ResultAssembler.init/2` would have returned a caller a task missing every
earlier turn — right in the store, wrong on the wire.

**The exchange, not just the agent's half, is the history.** The incoming
message is appended on every turn, including the first, so a single-turn task's
history contains what the user said. This is what §3.2.4 means by history, and
without it `historyLength` caps a list that only ever had one thing in it.

**Continuation implies context.** §3.4.3 requires an agent to infer `contextId`
from the task when only `taskId` is given; a follow-up previously minted a fresh
context id, which would have made a resumed task change context mid-exchange.
The same section requires rejecting a *mismatching* `contextId`, so a stated
context that disagrees with the task is now `invalid_params`. Ignoring it would
have been worse than either alternative: the client's explicit instruction would
have been silently overridden.

**`historyLength` is a view over the response, never a mutation.** One
`truncate_history/2` is applied by `GetTask`, `SendMessage` and `ListTasks`
alike. A negative value is ignored rather than passed to `Enum.take/2`, whose
negative-count semantics would invert the meaning and return the *oldest* n.

**The REST binding parses it from the query string.** §11.5: a GET has no body,
so its request parameters are camelCase query parameters —
`GET /tasks/{id}?historyLength=10`. This gap predates the change and was
invisible while both bindings ignored the field; honouring it on JSON-RPC alone
turned a passing MUST (`CORE-HIST-002`) red, because the two bindings then
disagreed. Fixing one binding of a shared field means fixing both.

## Consequences

Turn two of a task no longer resets it. Any caller that relied on re-sending an
existing `taskId` to get a clean projection was relying on a bug, but the
behaviour change is real and observable.

History grows unboundedly for a long-lived task: every turn appends the user's
message, and the store keeps the whole task. `historyLength` bounds the
*response*, not the store. A task store with retention policy is the eventual
answer; the ETS default has none, exactly as it has none for tasks themselves.

The seeded projection is not persisted until the executor's first emit, so a
task whose executor emits nothing still never reaches the store. That is
unchanged, pre-existing behaviour, not something this change introduces.

Six requirements move to passing (`CORE-HIST-001` through `006`), taking SHOULD
compatibility from 28.6% to 85.7%.

**`STREAM-SUB-002` is deliberately still failing.** It needs `resubscribe/2` to
hold a stream open on a non-terminal task with no live execution, waiting for a
later turn's events — `EventStream.stream/3` already supports exactly that with
`monitor: nil`. The reason it is not done here is that an open-ended subscribe
needs an idle-timeout policy, and `A2A.Plug.SSE` only notices a disconnected
client when a chunk write fails, which needs an event to send. Holding streams
open without first deciding that policy trades a failing test for a socket leak.
