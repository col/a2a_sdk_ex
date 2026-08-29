# Data model

[← Architecture](../architecture.md)

## Decision in brief

The core A2A types are **hand-written idiomatic Elixir structs**, with a
dedicated codec (`A2A.JSON`) owning proto3-JSON wire fidelity. We use the A2A
`.proto` and the v1.0 specification as the *authority* for shapes and field
names, but we do **not** generate code from the proto.

Rationale and alternatives considered:
[ADR-0004](decisions/0004-hand-written-types.md).

## Why not generate from proto?

Both reference SDKs generate their types from the A2A `.proto` (Python:
`a2a_pb2`; JS: `ts-proto` output). That guarantees wire fidelity but leaks proto
artifacts into the public API: integer enums, `_UNSPECIFIED` zero values, oneof
fields as awkward wrappers. Crucially, **our two transports use proto3-JSON, not
protobuf binary** — so we must write and own a JSON codec regardless of whether
the structs are generated. Generating buys us little while costing us an ugly
public API. If/when gRPC (binary) lands, a generated wire layer can sit *behind*
these public structs — see [ADR-0004](decisions/0004-hand-written-types.md) and
[Scope and roadmap](scope-and-roadmap.md).

## Core structs (`A2A.Types.*`)

| Struct | Shape (fields abbreviated) |
| --- | --- |
| `Message` | `message_id`, `context_id`, `task_id`, `role`, `parts`, `metadata`, `extensions`, `reference_task_ids` |
| `Task` | `id`, `context_id`, `status`, `artifacts`, `history`, `metadata` |
| `TaskStatus` | `state`, `message`, `timestamp` |
| `Part` | tagged struct: `%Part{kind: :text \| :file \| :data, ...}` |
| `Artifact` | `artifact_id`, `name`, `description`, `parts`, `metadata`, `extensions` |
| `TaskStatusUpdateEvent` | `task_id`, `context_id`, `status`, `final?`, `metadata` |
| `TaskArtifactUpdateEvent` | `task_id`, `context_id`, `artifact`, `append?`, `last_chunk?`, `metadata` |
| `AgentCard` | `name`, `description`, `supported_interfaces`, `provider`, `version`, `capabilities`, `security_schemes`, `skills`, `default_input_modes`, `default_output_modes`, `signatures`, … |
| `AgentCapabilities` | `streaming?`, `push_notifications?`, `extended_agent_card?`, `extensions` |
| `AgentInterface` | `url`, `protocol_binding`, `tenant`, `protocol_version` |
| `AgentSkill`, `AgentProvider`, `AgentExtension` | descriptive metadata |
| security | `SecurityScheme` (variants: api_key / http / oauth2 / oidc / mtls), `SecurityRequirement` |
| `TaskPushNotificationConfig` | webhook config bound to a task |

### Enums as atoms

`TaskState` is an atom, not an integer:

```
:submitted | :working | :completed | :failed | :canceled
| :input_required | :auth_required | :rejected
```

`Role` is `:user | :agent`. The codec maps these to/from the proto3-JSON string
names (e.g. `:input_required ⇄ "TASK_STATE_INPUT_REQUIRED"`). The proto
`_UNSPECIFIED` zero value is treated as invalid input on decode, never produced
on encode.

### `Part` as a tagged struct

The proto models `Part` as a oneof; the JS SDK uses a `$case`-tagged union. In
Elixir this is the one place the reference design ports cleanly and idiomatically:

```elixir
%A2A.Types.Part{kind: :text, text: "hello"}
%A2A.Types.Part{kind: :file, bytes: <<...>>, mime_type: "image/png", name: "a.png"}
%A2A.Types.Part{kind: :data, data: %{"k" => "v"}}
```

`SendMessageResponse` (`task | message`) and the streamed `StreamResponse`
(`task | message | status_update | artifact_update`) are likewise represented as
tagged structs, so pattern matching is exhaustive and explicit.

## `A2A.JSON` — the wire codec

A single module owns proto3-JSON fidelity, which is the entire risk surface of
hand-writing types. Responsibilities:

- **Field naming:** snake_case structs ⇄ camelCase JSON.
- **Enums:** atom ⇄ proto3-JSON SCREAMING_SNAKE string names.
- **Large integers:** encoded as strings on the wire (JSON's 53-bit safe-integer
  limit), matching the reference SDKs, so numeric fields survive a JS peer.
- **Bytes:** file `raw` bytes ⇄ base64.
- **Metadata:** the proto `Struct` type ⇄ a plain Elixir map.
- **Timestamps:** ISO-8601 strings.

`encode/1` and `decode/2` (the latter takes the expected type) are the whole
public surface; transports call them and never touch JSON shape directly.

## Wire-fidelity testing

Because we hand-write the structs, interop is guaranteed by tests, not by a
shared generator:

- **Round-trip fixtures** captured from the Python and JS SDKs: decode → struct →
  encode must reproduce the reference JSON byte-for-byte (modulo key order).
- **Golden files** per message type checked into the test suite.
- **Property tests** generating structs, asserting `decode(encode(x)) == x`.

See [Scope and roadmap](scope-and-roadmap.md) for how this corpus is sourced.

## Related

- [Request handling](request-handling.md) — how these structs flow through an execution.
- [Transports](transports.md) — where `A2A.JSON` is invoked.
- [ADR-0004](decisions/0004-hand-written-types.md) — the decision record.
