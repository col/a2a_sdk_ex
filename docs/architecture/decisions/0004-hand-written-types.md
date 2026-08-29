# 4. Hand-written idiomatic types, not generated from proto

Date: 2026-08-29
Status: Accepted

## Context

The A2A `.proto` file is the source of truth for wire shapes, and both reference
SDKs generate their types from it (Python: `a2a_pb2`; JS: `ts-proto`). Generated
types guarantee wire fidelity but leak proto artifacts into the public API:
integer enums, `_UNSPECIFIED` zero values, oneof fields as awkward wrappers.

Critically, v1's two transports use **proto3-JSON, not protobuf binary**
([ADR-0003](0003-jsonrpc-and-rest-transports.md)). A JSON codec (camelCase
mapping, enum names, large-int-as-string, base64 bytes) must be written and
owned regardless of whether the structs are generated. So generating structs
buys little while imposing an un-idiomatic public API on Elixir users.

## Decision

Hand-write **idiomatic Elixir structs** (`A2A.Types.*`) — `TaskState` as atoms,
`Part` as a tagged struct, snake_case fields — with a dedicated `A2A.JSON` codec
owning proto3-JSON wire fidelity. The `.proto`/spec is the authority for shapes;
we do not generate from it.

## Consequences

- Clean, documented, idiomatic public API — the biggest ergonomic win for Elixir
  adopters.
- We own wire fidelity by hand. This risk is mitigated by golden round-trip
  tests against corpora captured from the reference SDKs, plus property tests
  (see [Data model](../data-model.md)).
- Spec changes must be tracked and applied manually rather than regenerated.
- If/when gRPC (binary) lands, a **generated wire layer** can sit behind these
  public structs, keeping the public API stable
  ([ADR-0003](0003-jsonrpc-and-rest-transports.md)).
