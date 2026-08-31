# 16. Direct message responses

Date: 2026-08-31
Status: Accepted

## Context

`SendMessage` returns "a [`Task`] representing the processing of the message, OR
a [`Message`]: a direct response message (for simple interactions that don't
require task tracking)" (spec §3.1.1). The streaming form is narrower still —
§3.1.2: "the stream MUST contain exactly one `Message` object and then close
immediately. No task tracking or updates are provided."

The type surface already covered this: `SendMessageResponse` is a oneof with a
`message/1` constructor, and `A2A.Server.StreamFrame.of/1` already mapped a
`%Message{}` to `StreamResponse.message/1`. What was missing was any way for an
executor to *produce* one. Every path created a task, so `DM-MSG-001` failed and
`examples/compliance_server` carried a "Not implemented" note for the one TCK
scenario it could not serve.

## Decision

**An event whose payload is a bare `%Message{}` is a direct reply.**
`TaskUpdater.reply/2` broadcasts one, terminal, and persists nothing — there is
no task to save. `DefaultHandler.fold_event/2` halts on it with `{:message, msg}`
rather than folding it into a projection, and `send_message/3` returns
`{:ok, %Message{}}`.

This works because nothing else ever broadcasts a bare `Message`. That is worth
stating explicitly, because `ResultAssembler.apply/2` *does* have a `%Message{}`
clause — [ADR-0015](0015-multi-turn-continuation.md) uses it to seed the
incoming user message into history. But seeding applies the message to the
projection **directly**, never through the event stream, so the two uses cannot
collide. A future emitter of `Message` events would break that, which is why the
clause carries a comment saying so.

**The streaming form needs no special case.** `StreamFrame.of/1` already maps
`%Message{}`, and the event is terminal, so `EventStream` yields exactly one
frame and closes — precisely the §3.1.2 requirement, for free.

**Both bindings render the oneof.** `A2A.Plug.JSONRPC` and `A2A.Plug.REST` each
gained a `Message` arm alongside the `Task` one.

## Consequences

`send_message/3`'s return type widens to `{:ok, Task.t() | Message.t()}`. The
`A2A.Server.RequestHandler` behaviour already declared that union, so no
callback contract changed — the implementation had simply been narrower than the
behaviour it satisfied.

An executor that calls `reply/2` and then keeps emitting will find the later
events have no task to attach to. `reply/2` documents that it ends the
interaction; it does not enforce it, because enforcement would mean the updater
carrying "already replied" state for a case that is a programming error either
way.

A task id and a PubSub subscription are still allocated for a request that turns
out to be answered directly — the handler cannot know which it will be until the
executor decides. Nothing is persisted, so the cost is one unused id.

`DM-MSG-001` passes, and `examples/compliance_server` now implements every
scenario the TCK's Gherkin sources define.
