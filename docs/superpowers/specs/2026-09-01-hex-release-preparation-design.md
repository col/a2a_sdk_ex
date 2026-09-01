# Hex Release Preparation — Design

**Status:** Approved
**Date:** 2026-09-01
**Branch:** `throng/AA-18`

## Goal

Prepare `a2a_sdk_ex` for its **initial public release to [hex.pm](https://hex.pm)**
as version `0.1.0`. This covers four areas: package identity/metadata,
ExDoc/HexDocs documentation, an automated tag-triggered release pipeline, and the
supporting release artifacts (CHANGELOG, README, runbook).

This is release *infrastructure and documentation* work. It changes no runtime
behaviour of the library — the one code-level change is renaming the OTP
application atom, and the moduledoc audit, neither of which alters logic.

## Background & constraints

- This is genuinely the first release: **no git tags exist yet**.
- The hex package name **`a2a` is already taken** (HTTP 200 on the hex API).
  **`a2a_sdk` is available** (404). We publish as `a2a_sdk`.
- **Hex 2.4 authentication change (investigated):** Hex 2.4 replaced
  password-based *CLI* auth with an OAuth 2.0 device flow and requires 2FA for
  *OAuth tokens* to gain write permission. This does **not** block CI publishing:
  generated **API keys do not require TOTP validation**, so the
  `HEX_API_KEY` + `mix hex.publish --yes` flow used by CI still works.
  **Trusted Publishing (OIDC, keyless)** is on Hex's roadmap but **not yet
  available**, so it is out of scope for this release and noted as a future swap.
  Sources: <https://hex.pm/blog/hex-v24-released>,
  <https://hexdocs.pm/hex/Mix.Tasks.Hex.Publish.html>, <https://hex.pm/docs/publish>.
- Maintainer: **Colin Harris (@col)**. Repo stays `github.com/col/a2a_sdk_ex`.

## Non-goals (YAGNI for v0.1.0)

- Trusted publishing / OIDC keyless auth (not available on Hex yet).
- gRPC transport, multi-tenant scoping (already deferred elsewhere).
- `CONTRIBUTING.md`, issue templates, other community scaffolding.
- Changing the `examples/` beyond their path-dep atom; they remain unpublished.
- A pre-release (`-rc`) version — plain `0.1.0` already signals pre-1.0
  instability by SemVer convention.

---

## Section 1 — Package identity & `mix.exs`

### Rename `:a2a` → `:a2a_sdk`

The hex package name and OTP application atom become `a2a_sdk`. **The module
namespace `A2A.*` is unchanged** — hex package name and module namespace need not
match (cf. `phoenix_pubsub` → `Phoenix.PubSub`).

Rename scope (verified by grep — deliberately small):

- `mix.exs`: `app: :a2a` → `app: :a2a_sdk`, add explicit `name: "a2a_sdk"` in the
  `package` block.
- `examples/echo_server/mix.exs`: path-dep `{:a2a, path: "../.."}` → `{:a2a_sdk, path: "../.."}`.
- `examples/compliance_server/mix.exs`: same path-dep change.

There is **no `config/` directory** and **no `Application.get_env(:a2a, …)`**
usage, so no config keys change. The implementation must nonetheless re-grep for
any `:a2a` atom, `a2a` in `examples/*/README.md`, and `mix run`/dep references
before declaring the rename complete.

### `package` block (target shape)

```elixir
defp package do
  [
    name: "a2a_sdk",
    maintainers: ["Colin Harris (@col)"],
    licenses: ["Apache-2.0"],
    links: %{
      "GitHub" => @source_url,
      "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
      "A2A Protocol" => "https://a2a-protocol.org/v1.0.0/specification/"
    },
    files: ~w(lib priv/proto/PROTO_VERSION mix.exs README.md CHANGELOG.md LICENSE)
  ]
end
```

- Adds `LICENSE` and `CHANGELOG.md` to the packaged tarball (were missing).
- `version` stays `0.1.0`; `@source_url` stays `github.com/col/a2a_sdk_ex`.

---

## Section 2 — ExDoc / HexDocs documentation

### `docs` block (target shape)

```elixir
defp docs do
  [
    main: "readme",
    source_url: @source_url,
    source_ref: "v#{@version}",
    extras: [
      "README.md",
      "CHANGELOG.md"
      # plus the docs/architecture/*.md guides, grouped (see below)
    ],
    groups_for_extras: [
      Guides: Path.wildcard("docs/architecture/*.md")
    ],
    groups_for_modules: [
      Types: [~r/^A2A\.Types\./],
      Codec: [A2A.JSON],
      Server: [~r/^A2A\.Server\./],
      Transport: [~r/^A2A\.Plug\./, A2A.Standalone],
      Errors: [A2A.Error]
    ]
  ]
end
```

Notes:

- `source_ref: "v#{@version}"` makes HexDocs "source" links point at the tagged
  commit rather than a moving `main`.
- **`extras`**: README + CHANGELOG + the existing `docs/architecture/*.md` guides
  under a **Guides** group. The current stale reference to a single
  `docs/superpowers/specs/*` file is **removed** — internal design/spec docs do
  not ship to public HexDocs. (Exact extras/grouping mechanics — including
  whether ADR records are surfaced via a curated Guides index page vs. individual
  extras — are finalized in the plan; the intent is a clean sidebar, not ~12 raw
  ADR extras.)
- `groups_for_modules` regexes are illustrative; the plan pins the exact public
  module list (below). `@moduledoc false` modules are hidden regardless of group.

### Public / internal split (the reviewed decision)

**Public** — receive a concise, end-user `@moduledoc`; appear in HexDocs:

- `A2A`
- `A2A.Error`
- `A2A.JSON`
- All `A2A.Types.*` (agent_card, artifact, enums, events, field, message, part,
  push_notifications, requests, security, task, task_status)
- `A2A.Server.Supervisor`
- `A2A.Server.AgentExecutor` (behaviour the user implements)
- `A2A.Server.RequestHandler` (behaviour)
- `A2A.Server.DefaultHandler`
- `A2A.Server.TaskStore` (+ behaviour)
- `A2A.Server.TaskUpdater`
- `A2A.Server.RequestContext`
- `A2A.Plug.Router`
- `A2A.Standalone`

**Internal** — `@moduledoc false`, hidden from HexDocs:

- `A2A.Server.Execution`, `.EventStream`, `.Events`, `.ResultAssembler`,
  `.StreamFrame`
- `A2A.Server.PushDispatcher` (+ `.Supervisor`), `.PushSender` (+ `.Default`),
  `.PushConfigStore` (+ `.ETS`), `A2A.Server.TaskStore.ETS`
- `A2A.Plug.JSONRPC`, `A2A.Plug.REST`, `A2A.Plug.SSE`
  (users mount `A2A.Plug.Router`, not the sub-plugs)
- `A2A.JSON.Naming` (codec helper)
- `A2A.Scope`, `A2A.User`
- `Mix.Tasks.A2A.GenProto`

### Moduledoc audit rules (apply to the public set only)

The current moduledocs were written for maintainers. Rewrite them to be:

1. **End-user targeted** — "how do I use this to build an agent," not "how/why it
   was built."
2. **Concise** — resist verbosity. A short paragraph on what it is + a minimal
   usage example where it helps. Cut historical/rationale prose.
3. **No links** to `docs/architecture/*` or ADR records.
4. **Present-tense, current-state** — describe what exists now and how to call it.
   No "used to be," no design justification, no roadmap asides.

---

## Section 3 — Release automation (CI publish on tag)

### CI dependency: make `ci.yml` reusable

The release must publish **only if CI is green on the tagged commit**. GitHub
Actions cannot wait on a *separate* workflow for a tag trigger, so `ci.yml` is
made callable and the release workflow invokes it as a gating job.

- `ci.yml` `on:` gains `workflow_call` (keeps existing `push` and `pull_request`).
  No other change to `ci.yml`'s jobs (test matrix, proto, compliance).

### New `.github/workflows/release.yml`

- **Trigger:** `push` of a tag matching `v*` (e.g. `v0.1.0`).
- **`test` job:** `uses: ./.github/workflows/ci.yml` — runs the full matrix +
  proto + compliance against the tagged commit.
- **Version-guard step (in publish job):** assert the tag (`${GITHUB_REF_NAME}`
  without leading `v`) equals `@version` in `mix.exs`; fail fast on mismatch so a
  mistyped/unbumped tag never publishes.
- **`publish` job:** `needs: test`. Checkout → `erlef/setup-beam` (newest pair,
  Elixir 1.20 / OTP 29) → `mix deps.get` → version guard → `mix hex.publish --yes`
  with `HEX_API_KEY` from the `HEX_API_KEY` repo secret. `--yes` also publishes
  docs to HexDocs with no prompts.

Because `publish` needs `test`, and `test` is the whole CI suite, "publish only if
CI passes" is enforced structurally.

### Manual one-time setup (documented; cannot be automated here)

1. On hex.pm: enable 2FA on the account (account-hygiene; does not affect the CI
   key path).
2. Generate a dedicated write key:
   `mix hex.user key generate --permission api:write --key-name a2a-sdk-ci`.
3. Add it as the `HEX_API_KEY` secret under GitHub repo Settings → Secrets and
   variables → Actions.

### Release runbook (documented in-repo)

1. Update `CHANGELOG.md` (move `Unreleased` → the release version); bump
   `@version` in `mix.exs` if needed.
2. Commit; merge to `main`; confirm `ci.yml` is green on `main`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. `release.yml` re-runs CI on the tag, then publishes.
5. Verify on `hex.pm/packages/a2a_sdk` and `hexdocs.pm/a2a_sdk`.

---

## Section 4 — CHANGELOG, README, verification

### `CHANGELOG.md` (new)

- [Keep a Changelog](https://keepachangelog.com/) format, semver headings.
- `## [0.1.0] - <release date>` entry summarizing the initial surface: typed
  foundation (A2A v1.0 types + proto3-JSON codec), server runtime (blocking +
  streaming send, get/cancel/list/subscribe, push notifications), both HTTP
  transports (JSON-RPC + REST, optional Bandit standalone).
- Added to `package.files` and docs `extras`.

### README updates

- Install snippet → `{:a2a_sdk, "~> 0.1.0"}`.
- Add HexDocs + Hex.pm badges/links.
- Replace any `:a2a` atom references with `:a2a_sdk`.
- Keep the honest "Status" section as-is (candid about early stage).

### Verification before "done"

- `mix precommit` green (format, compile-warnings-as-errors, credo, test,
  dialyzer).
- `mix docs` builds with **no warnings or broken references** (catches removed
  spec-extra link, bad module refs).
- `mix hex.build` succeeds; inspect the packaged file list (e.g.
  `mix hex.build --unpack` into a temp dir) to confirm `lib/`,
  `priv/proto/PROTO_VERSION`, `mix.exs`, `README.md`, `CHANGELOG.md`, `LICENSE`
  are present and **no internal/test/spec files leaked**.
- `examples/echo_server` and `examples/compliance_server` still compile against
  the renamed path-dep.
- Dry-run publish is **not** performed automatically (avoids an accidental real
  publish); the actual publish happens only via a pushed tag with the secret set.

---

## Implementation ordering (for the plan)

1. **Rename + `mix.exs` metadata** (package block, name, files, links,
   maintainers) + examples path-deps.
2. **CHANGELOG.md** + README updates.
3. **Moduledoc audit** + `@moduledoc false` on internals + `docs` block
   (`groups_for_modules`, extras, `source_ref`).
4. **CI reusability** (`workflow_call`) + **`release.yml`**.
5. **Verification pass** (`precommit`, `docs`, `hex.build --unpack`, examples
   compile).

Each step is committed and pushed with `[no ci]` between plan tasks; a final
commit triggers CI and the PR is marked ready for review. The `HEX_API_KEY`
secret setup and the actual tag push remain manual actions for the maintainer.
