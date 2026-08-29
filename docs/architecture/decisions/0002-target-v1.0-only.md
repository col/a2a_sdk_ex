# 2. Target A2A v1.0 only

Date: 2026-08-29
Status: Accepted

## Context

The A2A protocol has a current version, **v1.0**, and a legacy **v0.3**. Both
reference SDKs target v1.0 but ship a substantial opt-in v0.3 backward-
compatibility layer: a parallel type set plus bidirectional translators plus
legacy routes/transports. Per the feature inventory, this compat layer roughly
**doubles the type surface** in both SDKs.

The ecosystem is actively migrating to v1.0.

## Decision

v1 implements **A2A v1.0 only**. No v0.3 compatibility layer.

## Consequences

- The type model and codec stay small and focused on one wire format.
- An Elixir agent cannot (yet) interoperate with peers still on v0.3. Given the
  server-first scope ([ADR-0001](0001-server-first-scope.md)) and the ecosystem
  trajectory, this is acceptable for v1.
- If demand appears, v0.3 compat can be added later as a **separate optional
  package** (as both reference SDKs structure it), without touching the v1.0
  core. It is designed *around*, not into.
