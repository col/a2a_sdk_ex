# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-01

Initial public release.

### Added

- **Typed foundation** — hand-written `A2A.Types.*` structs for the full A2A
  v1.0 type surface and the `A2A.JSON` proto3-JSON codec.
- **Server runtime** (`A2A.Server.*`) — process-per-task execution over an OTP
  supervision tree: blocking `SendMessage`/`GetTask`, streaming
  `SendStreamingMessage`/`SubscribeToTask`, `CancelTask`, and `ListTasks`, with
  an ETS-backed `TaskStore`.
- **HTTP transports** — JSON-RPC and REST behind one handler
  (`A2A.Plug.Router`), plus an optional Bandit-backed `A2A.Standalone`.
- **Push notifications** — opt-in webhook config CRUD on both bindings and
  best-effort per-task delivery.

[Unreleased]: https://github.com/col/a2a_sdk_ex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/col/a2a_sdk_ex/releases/tag/v0.1.0
