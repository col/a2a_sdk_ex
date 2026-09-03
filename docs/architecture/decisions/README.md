# Architecture Decision Records

These ADRs capture the significant, hard-to-reverse decisions behind the A2A
Elixir SDK, using [Michael Nygard's format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
(Context / Decision / Consequences). One decision per file. They are immutable
once accepted; a later decision that changes course gets a new ADR that
supersedes an earlier one.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-server-first-scope.md) | Server-first scope | Accepted |
| [0002](0002-target-v1.0-only.md) | Target A2A v1.0 only | Accepted |
| [0003](0003-jsonrpc-and-rest-transports.md) | Ship JSON-RPC + REST behind one handler | Accepted |
| [0004](0004-hand-written-types.md) | Hand-written idiomatic types | Accepted |
| [0005](0005-pubsub-process-model.md) | Process-per-task + Phoenix.PubSub | Accepted |
| [0006](0006-plug-first-mounting.md) | Plug-first, mountable HTTP layer | Accepted |
| [0007](0007-ets-task-store.md) | ETS task store behind a behaviour | Accepted |
| [0008](0008-v1-feature-tiers.md) | v1 feature tiers | Accepted |
| [0009](0009-eventstream-termination.md) | EventStream — shared stream, three-signal termination | Superseded in part by 0017 |
| [0010](0010-jsonrpc-transport-first.md) | JSON-RPC transport first; REST follows | Accepted |
| [0011](0011-rest-binding-and-cancel-list.md) | REST binding, `tasks/cancel`, and `tasks/list` land | Accepted |
| [0012](0012-push-notifications.md) | Push notification config CRUD + best-effort delivery engine | Accepted |
| [0013](0013-spec-faithful-error-representation.md) | Spec-faithful error representation on both bindings | Accepted |
| [0014](0014-request-validation-and-task-id-semantics.md) | Request validation: service parameters and task-identifier semantics | Accepted |
| [0015](0015-multi-turn-continuation.md) | Multi-turn continuation: seeded executions and exchange history | Accepted |
| [0016](0016-direct-message-responses.md) | Direct message responses | Accepted |
| [0017](0017-streams-terminate-at-task-terminal.md) | Streams terminate at task-terminal only | Accepted |
| [0018](0018-identity-ownership-and-extended-card.md) | Identity resolution, per-owner storage isolation, and the authenticated extended card | Accepted |
| [0019](0019-client-design.md) | Client design: facade + transport behaviour, injectable HTTP, header-passthrough auth | Accepted |

ADRs 0001–0008 were taken together during initial architecture planning (2026-08-29),
informed by a feature inventory of the official
[Python](https://github.com/a2aproject/a2a-python) and
[JavaScript](https://github.com/a2aproject/a2a-js) SDKs.
