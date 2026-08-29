# 3. Ship JSON-RPC + REST behind one transport-agnostic handler

Date: 2026-08-29
Status: Accepted

## Context

A2A defines three wire bindings: **JSON-RPC** (the primary/default, with the
richest streaming story over SSE), **HTTP+JSON/REST**, and **gRPC**. Both
reference SDKs implement all three behind a single transport-agnostic request
handler, so agent logic is written once.

In Elixir, JSON-RPC and REST are both HTTP+JSON over Plug and share the bulk of
their implementation (the same handler, the same `A2A.JSON` codec, the same SSE
mechanics). gRPC is heavier: it needs a protobuf toolchain and a separate server
stack, for the least-used binding.

## Decision

v1 ships **JSON-RPC and REST**, both delegating to **one
`A2A.Server.RequestHandler`**. gRPC is deferred but the handler boundary is
designed so gRPC can be added as a third adapter without changing agent code.

## Consequences

- Two transports for close to the cost of one, since they share the HTTP layer
  and codec.
- The "one handler, N transports" boundary is honoured from day one, so the
  design does not have to be retrofitted for gRPC.
- gRPC users are unserved in v1. When added, gRPC brings a generated
  protobuf-binary wire layer that sits *behind* the hand-written public structs
  ([ADR-0004](0004-hand-written-types.md)).
- SSE streaming is implemented once and reused by both bindings
  (see [Transports](../transports.md)).
