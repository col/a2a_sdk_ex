# 1. Server-first scope

Date: 2026-08-29
Status: Accepted

## Context

The A2A protocol has two sides: **servers** (host an agent, exposing
capabilities over the protocol) and **clients** (discover and drive agents).
Both official SDKs (Python, JavaScript) implement both sides. Building both well
is a large surface for a brand-new library, and the two sides share little code
beyond the type model.

Elixir/OTP is especially strong for the *server* concerns of A2A —
long-running, concurrent, streaming, cancellable, resumable executions — which
is also the most compelling story for adopting this SDK over the existing ones.

## Decision

v1 covers the **server side only**: hosting an A2A-compliant agent. The client
side is deferred to a later effort.

## Consequences

- The initial surface is halved, and focused on where Elixir differentiates.
- The type model ([ADR-0004](0004-hand-written-types.md)) is shared with a
  future client, so building the client later reuses it.
- Users who need to *call* A2A agents from Elixir in the interim must use HTTP
  directly or another language's client until the client side lands.
- Interop testing in v1 leans on the reference SDKs' *clients* as oracles
  against our server (see [Scope and roadmap](../scope-and-roadmap.md)).
