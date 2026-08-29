# Data model Phase 4 — Push notifications & task listing — design spec

**Status:** approved (brainstorm), pending implementation plan
**Date:** 2026-08-29
**Feature:** Phase 4 (final) of the data model (`A2A.Types.*` + `A2A.JSON` codec)
**Branch:** `throng/AA-8` (off `main`)

> Extends the [data model & codec design spec](2026-08-29-data-model-and-codec-design.md)
> (Phase 1) and the [Phase 3 security spec](2026-08-29-data-model-phase3-security-design.md).
> This spec realizes **Phase 4 — Push notifications & task listing** from §2.1 of
> the Phase-1 spec. It is the **last** data-model phase: after it lands, every
> proto message in the pinned A2A v1.0 surface has a hand-written struct and the
> `@deferred` manifest is empty.

## 1. Goal & scope

Deliver the **9 remaining** A2A v1.0 messages as hand-written `A2A.Types.*`
structs with field specs, wire up the final Phase-1 `:raw` placeholder that
references one of them, and empty the coverage `@deferred` list so the Tier-1
partition test proves the entire surface complete.

This phase adds **structs only** — no new codec machinery. Every wire type these
messages use (`:string`, `:int32`, `:bool`, `:timestamp`, `:struct`,
`{:enum, :task_state}`, `{:message, Mod}`, and `repeated`) already exists in the
codec and `A2A.Types.Field`.

### In scope

- The 9 Phase-4 messages:
  `TaskPushNotificationConfig`, `GetTaskPushNotificationConfigRequest`,
  `DeleteTaskPushNotificationConfigRequest`,
  `ListTaskPushNotificationConfigsRequest`,
  `ListTaskPushNotificationConfigsResponse`, `ListTasksRequest`,
  `ListTasksResponse`, `CancelTaskRequest`, `SubscribeToTaskRequest`.
- Re-typing the Phase-1 `:raw` placeholder on `SendMessageConfiguration` to the
  now-existing `TaskPushNotificationConfig`.
- Emptying the `@deferred` coverage manifest and updating its docs.
- Fixtures, generators, golden files, and unit tests for the 9 new types.

### Out of scope

- Any new codec machinery (none required — see §3).
- `StringList` — already delivered in Phase 3 (pulled forward for
  `SecurityRequirement`); it is **not** re-added here.
- Any server/transport/process/socket behaviour (unchanged from Phase 1).

## 2. The type surface

Files are organized **by domain**, not by delivery phase. The Phase-4 messages
split across two domains:

- A new file **`lib/a2a/types/push_notifications.ex`** for the push-config
  domain (the config container plus its Get/Delete/List request & response
  messages).
- The task listing/lifecycle RPC envelopes append to the existing
  **`lib/a2a/types/requests.ex`**, which already owns the core-flow request /
  response messages.

Every module exports `__a2a_proto_name__/0` and `__a2a_fields__/0`. None of the 9
messages is a `oneof` union, so none exports `__a2a_discriminator__/0`. All field
names / numbers / cardinality come straight from the pinned
`priv/proto/a2a.proto` (commit `cfc9d34bc41e368827eb6446d31f912e44f795c5`).

### 2.1 `push_notifications.ex`

**`TaskPushNotificationConfig`** — a container associating a push-notification
configuration with a task.

| Field | proto # | wire type |
| --- | --- | --- |
| `tenant` | 1 | `:string` |
| `id` | 2 | `:string` |
| `task_id` | 3 | `:string` |
| `url` | 4 | `:string` |
| `token` | 5 | `:string` |
| `authentication` | 6 | `{:message, A2A.Types.AuthenticationInfo}` |

`authentication` reuses the Phase-3 `AuthenticationInfo` struct — no new type.
`url` carries `field_behavior = REQUIRED` in the proto, but that is documentary
only; it stays a plain singular `:string` (the codec does not enforce required).

**`GetTaskPushNotificationConfigRequest`** and
**`DeleteTaskPushNotificationConfigRequest`** — identical shape:

| Field | proto # | wire type |
| --- | --- | --- |
| `tenant` | 1 | `:string` |
| `task_id` | 2 | `:string` |
| `id` | 3 | `:string` |

**`ListTaskPushNotificationConfigsRequest`** — note the **field numbers are not
in positional order** (`tenant` is #4, declared last, but `task_id` is #1); the
field spec keys off the proto number, not source order:

| Field | proto # | wire type |
| --- | --- | --- |
| `task_id` | 1 | `:string` |
| `page_size` | 2 | `:int32` (plain, `presence: :implicit`) |
| `page_token` | 3 | `:string` |
| `tenant` | 4 | `:string` |

**`ListTaskPushNotificationConfigsResponse`**:

| Field | proto # | wire type |
| --- | --- | --- |
| `configs` | 1 | `{:message, TaskPushNotificationConfig}`, `cardinality: :repeated` |
| `next_page_token` | 2 | `:string` |

### 2.2 `requests.ex` additions

**`ListTasksRequest`** — filtering / pagination parameters. The three `optional`
proto scalars map to `presence: :explicit` (so an explicit `0`/`false` is
distinguishable from unset), exactly as the existing
`GetTaskRequest.history_length` does:

| Field | proto # | wire type | notes |
| --- | --- | --- | --- |
| `tenant` | 1 | `:string` | |
| `context_id` | 2 | `:string` | |
| `status` | 3 | `{:enum, :task_state}` | unset ⇒ proto zero `_UNSPECIFIED`, rejected on decode / never emitted, per the standing enum rule |
| `page_size` | 4 | `:int32` | `optional` ⇒ `presence: :explicit` |
| `page_token` | 5 | `:string` | |
| `history_length` | 6 | `:int32` | `optional` ⇒ `presence: :explicit` |
| `status_timestamp_after` | 7 | `:timestamp` | ISO-8601 ⇄ `DateTime` per the codec's timestamp rule |
| `include_artifacts` | 8 | `:bool` | `optional` ⇒ `presence: :explicit` |

**`ListTasksResponse`** — the plain (non-`optional`) `int32` pagination fields
use `presence: :implicit`:

| Field | proto # | wire type | notes |
| --- | --- | --- | --- |
| `tasks` | 1 | `{:message, A2A.Types.Task}` | `cardinality: :repeated` |
| `next_page_token` | 2 | `:string` | |
| `page_size` | 3 | `:int32` | plain |
| `total_size` | 4 | `:int32` | plain |

**`CancelTaskRequest`**:

| Field | proto # | wire type |
| --- | --- | --- |
| `tenant` | 1 | `:string` |
| `id` | 2 | `:string` |
| `metadata` | 3 | `:struct` (`google.protobuf.Struct` ⇄ plain map) |

**`SubscribeToTaskRequest`**:

| Field | proto # | wire type |
| --- | --- | --- |
| `tenant` | 1 | `:string` |
| `id` | 2 | `:string` |

## 3. Codec — no change

This phase adds **no** shared machinery. Confirm-before-implement checklist,
each already exercised by an existing covered type:

- `:int32` + `presence: :explicit` — `GetTaskRequest.history_length`,
  `SendMessageConfiguration.history_length`.
- `:int32` + `presence: :implicit` — no existing plain int32 field, but the codec
  path is the same encoder/decoder as the explicit case minus the presence
  wrapper; covered by the new `ListTasksResponse` golden + property tests.
- `:timestamp` — `TaskStatus.timestamp`.
- `:struct` — `SendMessageRequest.metadata`, `Task.metadata`.
- `{:enum, :task_state}` — `TaskStatus.state`.
- `{:message, Mod}` repeated — `Task.artifacts`, `Message.content`.

If any of these turns out to need a codec tweak, that is a surprise the Tier-2
differential oracle will catch immediately; the design intent is struct-only.

## 4. Wiring the final `:raw` placeholder

`A2A.Types.SendMessageConfiguration.task_push_notification_config` (#2) is today a
`:raw` passthrough with a TODO naming this phase. Now that the struct exists:

- Field type `:raw` → `{:message, A2A.Types.TaskPushNotificationConfig}`.
- `@type` tightens from `map() | nil` to `TaskPushNotificationConfig.t() | nil`.

This mirrors how Phase 3 re-typed the `AgentCard` / `AgentSkill` security
placeholders. After this, **no `:raw` fields remain** in `A2A.Types.*` — the
`:raw` wire type stays in `Field.@type wire` as a general escape hatch but is
unused by shipped structs.

## 5. Coverage manifest

`test/support/coverage.ex`:

- Remove **all 9** `@deferred` entries — each becomes `covered` automatically via
  its module's `__a2a_proto_name__/0`. `@deferred` becomes `[]`.
- Update the moduledoc / typespec comment: `@deferred` is no longer "postponed to
  Phase 4" — it is the finished-state empty list, and any future proto release
  that adds a message will surface in *neither* set and fail the partition loudly
  (the drift guard still works with an empty deferred list).

The Tier-1 partition test (`proto_messages == covered ∪ deferred`, disjoint) then
proves the **entire** v1.0 message surface complete, with `@deferred == []`.

## 6. Testing strategy

TDD throughout; write the failing test first. Both `mix test` (proto excluded)
and `mix test --only proto` must end green, and `mix precommit` clean.

- **`test/a2a/types/push_notifications_test.exs`** — construction + decode unit
  tests for the 5 push-config types (including `authentication` nesting and the
  out-of-order field numbers on `ListTaskPushNotificationConfigsRequest`).
- **`test/a2a/types/requests_test.exs`** — extend with the 4 new request/response
  types (enum `status` filter, explicit-presence `optional` scalars, repeated
  `tasks`, `:timestamp` round-trip, `:struct` metadata).
- **`test/support/fixtures.ex`** — one representative non-trivial instance per new
  covered type; populate `SendMessageConfiguration.task_push_notification_config`
  in the existing fixture so the differential oracle exercises the re-typed field.
- **`test/support/generators.ex`** — `stream_data` generators for the 9 new types
  so the property / oracle cross-check covers them.
- **Golden files** — add at least a `TaskPushNotificationConfig` (with
  `authentication`) and a `ListTasksResponse` (repeated tasks + pagination ints)
  under `test/support/golden/` as the reference backstop on top of the oracle.

## 7. Risks & mitigations

- **Out-of-order field numbers on `ListTaskPushNotificationConfigsRequest`** →
  field spec keys off `number:`, not list position; the Tier-1 field-match test
  fails loudly on any number/name/cardinality mismatch.
- **Plain `int32` presence** (`ListTasksResponse.page_size`/`total_size`) → these
  are the first shipped non-`optional` int32 fields; a golden + property round-trip
  proves the zero-value handling (proto3 omits `0` on the wire) matches the oracle.
- **`status` enum zero on a filter field** → an unset `status` is
  `TASK_STATE_UNSPECIFIED`, which the standing rule rejects on decode / never
  emits; fixtures and generators use a concrete state. Same behaviour as every
  other enum field — no special-casing.
- **Codec surprise** → the design asserts struct-only; the Tier-2 oracle would
  catch any real gap on the first proto run.

## 8. Definition of done

- The 9 Phase-4 messages exist as `A2A.Types.*` with field specs, split by domain
  (`push_notifications.ex` + `requests.ex`); `@deferred == []`.
- No new codec logic added; `A2A.JSON` unchanged except as forced by tests (none
  expected).
- `SendMessageConfiguration.task_push_notification_config` re-typed to the real
  struct; no `:raw` fields remain in shipped structs.
- `mix test` green with no toolchain; `mix test --only proto` green with the
  Tier-1 partition holding over the **complete** surface (empty `@deferred`) and
  Tier-2 compliance passing over the new covered types.
- Golden round-trips pass for the added fixtures; `mix precommit` (format, Credo,
  Dialyzer) clean.
