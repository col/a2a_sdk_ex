# 7. ETS task store behind a behaviour; Ecto deferred

Date: 2026-08-29
Status: Accepted

## Context

Task and push-config persistence must be swappable (in-memory for dev/tests,
durable for production). The Python SDK ships in-memory plus a SQLAlchemy/Alembic
backend with configurable table names and optional field encryption; the JS SDK
ships in-memory only and leaves durable storage to the user.

A key Elixir-specific insight: because a running task is a live process
([ADR-0005](0005-pubsub-process-model.md)), the store is not the source of truth
for hot state — it is the durable **projection** used for `tasks/get`,
`tasks/list`, resubscribe catch-up, and restart recovery. That makes the store's
job simpler (storage, not concurrency control).

## Decision

Define `A2A.Server.TaskStore` and `A2A.Server.PushConfigStore` **behaviours**,
scoped by tenant/owner, and ship **ETS-backed defaults**. A first-party
Ecto/Postgres adapter is a documented **fast-follow package**, not part of core
v1.

## Consequences

- The core stays dependency-light; a working, streaming agent runs with no
  database.
- Persistence is a behaviour from day one, so an Ecto adapter (or any third-party
  store) drops in with no change to the handler or execution model. A shared
  **conformance test suite** keeps implementations honest.
- ETS state does not survive a node restart; production users needing durable
  history implement or await the Ecto adapter.
- Deferring Ecto avoids committing to schema/migration/table-name decisions
  before the behaviour has been exercised by a real agent. The Python SDK's
  configurable table names and field encryption are recorded as design inputs
  for that adapter (see [Persistence](../persistence.md)).
