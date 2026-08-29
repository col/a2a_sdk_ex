# Data model Phase 3 — Security schemes — design spec

**Status:** approved (brainstorm), pending implementation plan
**Date:** 2026-08-29
**Feature:** Phase 3 of the data model (`A2A.Types.*` + `A2A.JSON` codec)
**Branch:** `throng/AA-7` (off `main`)

> Extends the [data model & codec design spec](2026-08-29-data-model-and-codec-design.md)
> (Phase 1) and its Phase-2 follow-on. This spec realizes **Phase 3 — Security
> schemes** from §2.1 of that spec. It adds structs and the **one** piece of new
> shared codec machinery those structs require (proto `map<…>` support); it does
> not touch the harness machinery, which was built in full in Phase 1.

## 1. Goal & scope

Deliver the **14 security-scheme messages** of the A2A v1.0 surface as
hand-written `A2A.Types.*` structs with field specs, wire up the two Phase-2
`:raw` placeholders that reference them, and add generic proto-map support to the
codec so the map-typed security fields are modeled faithfully rather than passed
through untyped.

### In scope

- The 14 Phase-3 messages: `SecurityScheme`, `APIKeySecurityScheme`,
  `HTTPAuthSecurityScheme`, `OAuth2SecurityScheme`, `OpenIdConnectSecurityScheme`,
  `MutualTlsSecurityScheme`, `SecurityRequirement`, `OAuthFlows`,
  `AuthorizationCodeOAuthFlow`, `ClientCredentialsOAuthFlow`, `ImplicitOAuthFlow`,
  `PasswordOAuthFlow`, `DeviceCodeOAuthFlow`, `AuthenticationInfo`.
- **`StringList`** pulled forward from Phase 4 (§4) so `SecurityRequirement` is
  proto-faithful.
- Generic `{:map, :string, value}` codec support in `A2A.JSON` + `A2A.Types.Field`.
- Re-typing the Phase-2 `:raw` placeholders on `AgentCard` and `AgentSkill` to the
  now-existing structs.
- Coverage-manifest, fixtures, generators, golden-file, and unit-test updates.

### Out of scope

- The remaining 9 Phase-4 messages (push notifications & task listing) — they stay
  on `@deferred`.
- Any server/transport/process/socket behaviour (unchanged from Phase 1).

## 2. The type surface

New file **`lib/a2a/types/security.ex`** holding 15 modules (mirroring how
`lib/a2a/types/agent_card.ex` holds the whole Phase-2 cluster). Every module
exports `__a2a_proto_name__/0` and `__a2a_fields__/0`; the two union modules also
export `__a2a_discriminator__/0`. All field names/numbers/cardinality/oneofs come
straight from the pinned `priv/proto/a2a.proto` (commit
`cfc9d34bc41e368827eb6446d31f912e44f795c5`).

### 2.1 Leaf scheme structs

| Module | Fields (proto #) |
| --- | --- |
| `APIKeySecurityScheme` | `description` 1, `location` 2, `name` 3 — all `:string` |
| `HTTPAuthSecurityScheme` | `description` 1, `scheme` 2, `bearer_format` 3 |
| `OAuth2SecurityScheme` | `description` 1, `flows` 2 `{:message, OAuthFlows}`, `oauth2_metadata_url` 3 |
| `OpenIdConnectSecurityScheme` | `description` 1, `open_id_connect_url` 2 |
| `MutualTlsSecurityScheme` | `description` 1 |
| `AuthenticationInfo` | `scheme` 1, `credentials` 2 |

### 2.2 `SecurityScheme` union

Tagged union over the proto `oneof scheme`, following the `A2A.Types.Part`
pattern exactly (`:kind` discriminator via `__a2a_discriminator__/0`, one field
per oneof arm with `oneof: {:scheme, tag}`, `presence: :explicit`, constructor
helpers).

- `kind :: :api_key | :http_auth | :oauth2 | :open_id_connect | :mtls`
- Struct field names are the short idiomatic forms (`:api_key`, `:http_auth`,
  `:oauth2`, `:open_id_connect`, `:mtls`). The **`proto_name` stays exact**
  (`"api_key_security_scheme"`, `"http_auth_security_scheme"`,
  `"oauth2_security_scheme"`, `"open_id_connect_security_scheme"`,
  `"mtls_security_scheme"`) so the derived `json_name`
  (`"apiKeySecurityScheme"`, …) matches the proto3-JSON oracle. Only the internal
  struct key is shortened; nothing on the wire changes.
- Arm value types are `{:message, <the leaf struct>}` at numbers 1–5.

### 2.3 OAuth flow structs

| Module | Fields (proto #) |
| --- | --- |
| `AuthorizationCodeOAuthFlow` | `authorization_url` 1, `token_url` 2, `refresh_url` 3, `scopes` 4 `{:map,:string,:string}`, `pkce_required` 5 `:bool` |
| `ClientCredentialsOAuthFlow` | `token_url` 1, `refresh_url` 2, `scopes` 3 map |
| `ImplicitOAuthFlow` | `authorization_url` 1, `refresh_url` 2, `scopes` 3 map |
| `PasswordOAuthFlow` | `token_url` 1, `refresh_url` 2, `scopes` 3 map |
| `DeviceCodeOAuthFlow` | `device_authorization_url` 1, `token_url` 2, `refresh_url` 3, `scopes` 4 map |

`ImplicitOAuthFlow` and `PasswordOAuthFlow` are marked `deprecated` in the proto;
we still model them fully — the completeness harness requires the whole field set,
and a deprecated wire message must still decode.

### 2.4 `OAuthFlows` union

Same union pattern as `SecurityScheme`, over the proto `oneof flow`:

- `kind :: :authorization_code | :client_credentials | :implicit | :password | :device_code`
- Struct field names equal the proto field names (`:authorization_code` …), arms
  at numbers 1–5 with `oneof: {:flow, tag}`, value types `{:message, <flow>}`.

### 2.5 `SecurityRequirement` and `StringList`

- **`StringList`** — `list :: [String.t()]` at proto #1 (`type: :string,
  cardinality: :repeated`). Pulled forward from Phase 4; §4 covers the manifest
  consequence.
- **`SecurityRequirement`** — `schemes` at proto #1, typed
  `{:map, :string, {:message, StringList}}`. Idiomatic Elixir representation is a
  plain `%{String.t() => %StringList{}}`. On the wire this is
  `{"scheme-name": {"list": ["read","write"]}}`, exactly matching
  `map<string, StringList>`.

## 3. Codec change — generic map support

The only shared-machinery change. Today the codec has no proto-map wire type
(`AgentCard.security_schemes` is a `:raw` passthrough with a TODO explicitly
naming this phase).

### 3.1 Field spec

Add `{:map, key_wire, value_wire}` to `A2A.Types.Field`'s `@type wire`. In this
surface `key_wire` is always `:string`; `value_wire` is a scalar wire type
(`:string`, for OAuth `scopes`) or `{:message, Mod}` (for `StringList` and
`SecurityScheme`). Map fields keep **`cardinality: :singular`** — elixir-protobuf
reports proto map fields as non-repeated (confirmed empirically: the Phase-2
`AgentCard.security_schemes` field already passes the descriptor field-match test
as `:singular` today, and the proto-message-name filter already excludes synthetic
`…Entry` map messages).

### 3.2 `A2A.JSON`

Two new clauses, no per-struct logic (consistent with the codec's single-source
rule):

- **encode:** `nil` or empty map → `:skip` (proto3 omits empty maps); otherwise
  emit a JSON object mapping each string key to
  `encode_scalar(value_wire, entry_value)`.
- **decode:** a JSON object → `%{k => decode_scalar(value_wire, v)}`, preserving
  string keys; a non-map raw is a `{:error, {:type_mismatch, …}}`.

`decode_scalar/encode_scalar` already recurse into `{:message, Mod}`, so map
values that are messages (`StringList`, `SecurityScheme`) round-trip for free.

## 4. Coverage manifest

`test/support/coverage.ex`:

- Remove the 14 Phase-3 `@deferred` entries — each becomes `covered`
  automatically via its module's `__a2a_proto_name__/0`.
- Move `StringList` **out** of the Phase-4 `@deferred` list into covered (decision
  A from the brainstorm: `SecurityRequirement` cannot be modeled faithfully
  without it, and it is a trivial one-field message).
- `@deferred` shrinks to the remaining **9** Phase-4 messages
  (`TaskPushNotificationConfig`, `GetTaskPushNotificationConfigRequest`,
  `DeleteTaskPushNotificationConfigRequest`,
  `ListTaskPushNotificationConfigsRequest`,
  `ListTaskPushNotificationConfigsResponse`, `ListTasksRequest`,
  `ListTasksResponse`, `CancelTaskRequest`, `SubscribeToTaskRequest`).

The Tier-1 partition test then proves the entire security surface complete; only
the push/listing cluster remains deferred.

## 5. Wiring the Phase-2 `:raw` placeholders

Now that the referenced structs exist:

- `AgentCard.security_schemes` #8: `:raw` → `{:map, :string, {:message, SecurityScheme}}`.
- `AgentCard.security_requirements` #9: `:raw` repeated → `{:message, SecurityRequirement}` repeated.
- `AgentSkill.security_requirements` #8: `:raw` repeated → `{:message, SecurityRequirement}` repeated.

Their `@type` specs tighten from `map()` / `[map()]` to the real struct types. The
`agent_card`/`agent_skill` fixtures gain populated security data so the
differential oracle actually exercises the new map/message paths end-to-end.

## 6. Testing strategy

TDD throughout; write the failing test first. Both `mix test` (proto excluded)
and `mix test --only proto` must end green, and `mix precommit` clean.

- **`test/a2a/types/security_test.exs`** — construction + union-dispatch unit
  tests for all 15 new types (including the `:kind` discriminator on decode).
- **`test/a2a/json_test.exs`** — new map-codec rule tests: `map<string,string>`
  (OAuth `scopes`), `map<string,message>` (`SecurityRequirement.schemes`,
  `AgentCard.security_schemes`), empty-map-skips-on-encode, and decode round-trip.
- **`test/support/fixtures.ex`** — one representative non-trivial instance per new
  covered type; populate security fields on `agent_card` and `agent_skill`.
- **`test/support/generators.ex`** — `stream_data` generators for the new types so
  the property/oracle cross-check covers them.
- **Golden files** — add at least an `oauth2` `SecurityScheme` and a
  security-populated `AgentCard` under `test/support/golden/` as the reference
  backstop on top of the oracle.

## 7. Risks & mitigations

- **Map cardinality vs. the descriptor** → validated up front: the existing
  Phase-2 `AgentCard.security_schemes` field already passes the field-match test as
  `:singular`, so map fields carry `cardinality: :singular`. Any mismatch fails the
  Tier-1 field test loudly.
- **`StringList` phase bleed** → explicitly recorded here and in the manifest
  (decision A); Phase 4's spec/plan must not re-add it to `@deferred`.
- **Deprecated OAuth flows** → modeled fully regardless of the `deprecated`
  option; completeness requires the whole field set.
- **Verbose oneof proto names vs. idiomatic keys** → resolved by keeping
  `proto_name` exact and only shortening the internal struct key, so the wire form
  and oracle are untouched.

## 8. Definition of done

- The 14 Phase-3 messages + `StringList` exist as `A2A.Types.*` with field specs;
  `@deferred` holds exactly the 9 remaining Phase-4 messages.
- `A2A.JSON` encodes/decodes `map<string, scalar|message>` generically; no
  per-struct codec logic added.
- The Phase-2 `:raw` security placeholders are re-typed to real structs.
- `mix test` green with no toolchain; `mix test --only proto` green with the Tier-1
  partition holding and Tier-2 compliance passing over the new covered types.
- Golden round-trips pass for the added security fixtures; `mix precommit` (format,
  Credo, Dialyzer) clean.
