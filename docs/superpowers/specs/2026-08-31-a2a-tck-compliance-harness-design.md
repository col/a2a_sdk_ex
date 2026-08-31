# A2A TCK Compliance Harness — Design

- **Status:** Approved (pending spec review)
- **Date:** 2026-08-31
- **Branch:** `throng/AA-14`
- **Related:** [a2a-tck](https://github.com/a2aproject/a2a-tck) (upstream compliance suite)

## Summary

Make it easy — for a developer, for an agent working in a sandbox, and for CI —
to run the official [a2a-tck](https://github.com/a2aproject/a2a-tck) compliance
suite against an A2A agent built with this SDK, and to produce a report.

The **System Under Test (SUT)** for now is the existing `examples/echo_server`,
served over the JSON-RPC binding at `http://localhost:5001`. The TCK fetches the
agent card from `{sut-host}/.well-known/agent-card.json`, spins up a JSON-RPC
client, and runs a pytest-based suite that classifies requirements by RFC 2119
level (MUST / SHOULD / MAY), writing machine- and human-readable reports.

We are **not compliant yet**, and that is expected. The goal of this task is to
stand up the *measurement loop* — not to pass it. CI surfaces the report on every
build without failing the build.

## Goals

- A one-time, **documented** environment bootstrap (Python 3.11+, `uv`, a pinned
  TCK checkout) that a human uses to pre-configure a sandbox or dev machine.
- A single committed `scripts/run_tck.sh` that boots the echo server, waits for
  readiness, runs the TCK against it, collects the reports, and tears the server
  down — invoked identically by a developer, by an agent in a sandbox, and by CI.
- A **non-blocking** CI job that runs that script and uploads the reports as build
  artifacts, so the compliance report is visible on every build.

## Non-goals (explicitly out of scope for this task)

- **Baseline storage, trend tracking, PR-comment stats, and the regression gate.**
  Deferred by explicit decision. The CI job only *produces and uploads* a report;
  it does not compare against a prior run, comment on PRs, or fail on regression.
- **A dedicated conformance-fixture agent.** We test the existing echo server for
  now. Building a fixture whose job is to exercise as much of the spec surface as
  the library supports (so the score tracks the *library*, not the *example*) is a
  planned fast-follow, not part of this task. See "Known limitations".
- **New SDK protocol surface.** `tasks/cancel`, `tasks/list`, and the REST
  (HTTP+JSON) binding remain unimplemented; this task does not add them. Their
  absence will show up as TCK failures/skips — that is the point of measuring.
- **Making the bootstrap script-driven / sandbox-auto-runnable.** The bootstrap is
  documentation only. The user configures sandboxes from the doc before they start.

## Decisions (from brainstorming)

1. **Target: echo server first, migrate to a fixture later.** The CI and dev-flow
   plumbing is identical regardless of target, so we wire it against the thing that
   already exists (proves the whole loop cheaply) and treat a dedicated conformance
   agent as a fast-follow.
2. **Trend/regression/PR-comment: out of scope.** No baseline file, no gate, no
   comment. Report-only.
3. **CI: yes, non-blocking.** A `compliance` job runs the script, is marked
   `continue-on-error`, and uploads `reports/` as artifacts. It never fails the
   build.
4. **TCK version: pin a specific ref.** Recorded canonically as `TCK_REF` in this
   doc and the CI workflow. Pinned so our numbers move only when *we* change, and
   so CI can't break out from under us when upstream changes its tests.
5. **Orchestration: one committed `scripts/run_tck.sh`.** Humans, agents, and CI
   all invoke the same script — a single source of truth, no drift between local
   and CI steps.
6. **The TCK checkout is a pre-provided dependency, not something the script
   manages.** The script assumes the TCK is checked out at a sibling path and only
   *asserts its presence*; it does not clone or install it. CI, which has no
   pre-provisioned sibling, satisfies the dependency itself before calling the
   script.

### Pinned TCK ref

```
TCK_REF = 1.0.0.alpha2
```

Rationale: the TCK publishes both a `v0.2.x` line (older A2A spec) and a
`1.0.0.alphaN` line. This SDK targets **A2A spec v1.0**, so we pin the most recent
v1.0-line tag, `1.0.0.alpha2` (2026-05-27), which supports the JSON-RPC transport.
The implementer must confirm this ref actually runs against the echo server; if a
newer v1.0-line tag has shipped by implementation time, prefer it and update this
line plus the CI workflow together.

## Architecture

Four pieces, each with one responsibility.

### 1. Bootstrap documentation — `docs/tck-compliance.md`

Human/sandbox-prep facing. **Not executed by the script.** Lists the prerequisites
a host must have before anything runs and the exact commands to satisfy them:

- System prerequisites: Python 3.11+, [`uv`](https://github.com/astral-sh/uv),
  `git`, `jq`, plus the Erlang/Elixir toolchain (already present in this repo).
- The one-time TCK checkout + install into the sibling directory:

  ```bash
  # From the parent of the a2a_sdk_ex checkout:
  git clone --branch "$TCK_REF" https://github.com/a2aproject/a2a-tck.git a2a-tck
  cd a2a-tck
  uv venv
  uv pip install -e .
  ```

- How to run the harness (`scripts/run_tck.sh`) and where to find the reports.
- How to read the report (compatibility summary, per-requirement breakdown).
- How to bump the pinned ref (update `TCK_REF` in this doc **and** the CI workflow,
  re-clone, re-run).

This doc is what the user feeds into sandbox provisioning so future sandboxes come
up with Python + `uv` + the TCK sibling checkout already present.

### 2. `scripts/run_tck.sh` — the reproducible run

Given the prerequisites exist, this is the single command that produces a report.
Configuration is via environment variables with sensible defaults:

| Var | Default | Meaning |
| --- | --- | --- |
| `TCK_DIR` | `../a2a-tck` | Sibling checkout of the TCK (pre-provided dependency) |
| `SUT_PORT` | `5001` | Port the echo server listens on |
| `SUT_HOST` | `http://localhost:$SUT_PORT` | Base URL passed to the TCK as `--sut-host` |
| `REPORTS_DIR` | `reports/` (repo-local, git-ignored) | Where reports are collected |
| `READY_TIMEOUT` | `30` (seconds) | Max wait for the SUT to become ready |

Responsibilities, in order (see Data flow below). The script is **fully agnostic**
about the TCK ref — it checks only that `TCK_DIR` exists and contains a usable
`run_tck.py`. It does **not** clone, install, or verify the ref. The user controls
provisioning; the ref is pinned by whoever populates `TCK_DIR`.

### 3. CI job — `compliance` in `.github/workflows/ci.yml`

A new job parallel to the existing `test` and `proto` jobs, marked
`continue-on-error: true` so it never fails the overall run. It is the one place
with no pre-provisioned sibling checkout, so it satisfies the TCK dependency itself
(clone at `TCK_REF` into `../a2a-tck`, `uv` install) and then calls the same script.
Reports are uploaded as build artifacts (always, even on failure).

### 4. `.gitignore` entries

`reports/` (harness output) is git-ignored. The TCK checkout lives outside the repo
(sibling dir) so needs no ignore entry, but the entry is documented in case a user
relocates `TCK_DIR` inside the tree.

## Data flow

```
run_tck.sh
  |- resolve config (TCK_DIR, SUT_PORT, SUT_HOST, REPORTS_DIR, READY_TIMEOUT)
  |- assert TCK_DIR exists + has run_tck.py     --X--> error + exit 2  (dependency missing)
  |- boot echo server (background):             --X--> error + exit 3  (server won't start)
  |     (cd examples/echo_server && mix run --no-halt)   [deps assumed fetched]
  |- wait for readiness: poll GET $SUT_HOST/.well-known/agent-card.json
  |     until HTTP 200 or READY_TIMEOUT          --X--> teardown + exit 4  (never ready)
  |- run TCK: (cd $TCK_DIR && ./run_tck.py --sut-host $SUT_HOST ...)
  |- copy $TCK_DIR/reports/ -> $REPORTS_DIR (repo-local, git-ignored)
  \- EXIT trap: always kill the echo server (and its OS process group)
        exit code = TCK's exit code (callers decide whether that is fatal)
```

Robustness points:

- A `trap ... EXIT` guarantees the echo server (and its process group) is killed
  even on failure, timeout, or Ctrl-C — no orphaned Bandit listener on port 5001.
- Readiness is **polled**, not a fixed `sleep`, so the run is neither flaky nor
  needlessly slow.
- Distinct non-zero exit codes (2 = missing dependency, 3 = server failed to boot,
  4 = never became ready) make failures diagnosable from the exit status alone.
- Reports are copied into a repo-local, git-ignored dir so dev and CI find them in
  the same place.
- The script returns the TCK's own exit code; **callers** decide whether a
  non-passing TCK run is fatal. CI does not treat it as fatal (`continue-on-error`).

## CI job sketch

```yaml
compliance:
  runs-on: ubuntu-latest
  continue-on-error: true          # never fails the build (for now)
  steps:
    - uses: actions/checkout@v4
    - uses: erlef/setup-beam@v1
      with: {otp-version: "26", elixir-version: "1.16"}
    - uses: actions/setup-python@v5
      with: {python-version: "3.11"}
    - name: Install uv
      run: curl -LsSf https://astral.sh/uv/install.sh | sh
    - name: Check out and install the pinned TCK (sibling dir)
      run: |
        git clone --depth 1 --branch "1.0.0.alpha2" \
          https://github.com/a2aproject/a2a-tck.git ../a2a-tck
        cd ../a2a-tck && uv venv && uv pip install -e .
    - run: mix deps.get
    - run: (cd examples/echo_server && mix deps.get)
    - run: scripts/run_tck.sh
    - uses: actions/upload-artifact@v4
      if: always()
      with:
        name: tck-compliance-report
        path: reports/
```

`TCK_REF` (`1.0.0.alpha2`) is a literal in the workflow, mirrored from this doc;
the two must be bumped together. `run_tck.sh` must run the TCK inside the TCK's
`uv` virtualenv (e.g. via `uv run` / activating `.venv`), which the implementer
wires as part of the script's TCK-invocation step.

Per this repo's PR flow: intermediate commits use `[no ci]`; the compliance job is
first exercised on the final ready-for-review push.

## Testing / verification

This task is shell + docs + YAML — there are no Elixir units to TDD. "Done" is
defined by exercising the real loop and capturing evidence:

- Perform the one-time bootstrap **in the sandbox** exactly as written in
  `docs/tck-compliance.md`, proving the documented commands actually work.
- Run `scripts/run_tck.sh` end-to-end: confirm the echo server boots, the TCK runs
  against it, and `reports/` is produced with the expected files
  (`compatibility.json`, `compatibility.html`, `tck_report.html`,
  `junitreport.xml`).
- Capture the **actual** compliance summary the echo server currently achieves and
  record it in the PR description as our informational current-state (not a gate).
- Exercise the two most important failure modes:
  - missing `TCK_DIR` → clean error, exit 2, no orphaned server;
  - server never becomes ready → teardown fires, exit 4, no orphaned server.
- Confirm no `beam.smp` / Bandit process is left listening on `SUT_PORT` after any
  exit path.

## Known limitations / follow-ups

- **The score measures the example, not the library.** Because the SUT is the
  intentionally-minimal echo server (JSON-RPC only; `message/send`,
  `message/stream`, `tasks/get`, `tasks/resubscribe`), the compliance number
  conflates "the demo is minimal" with "the SDK is incomplete." A dedicated
  conformance-fixture agent is the honest signal and is the recommended fast-follow.
- **No trend or regression protection yet.** A regression could land unnoticed
  because nothing compares builds. Re-scoping the deferred baseline/gate work is the
  natural next step once the loop is trusted.
- **Single global ETS TaskStore.** Per the repo's known constraints, only one
  `A2A.Server.Supervisor` tree can run at once; the harness runs exactly one echo
  server, so this is not a problem here, but a fixture agent must respect it too.
- **TCK ref is alpha.** `1.0.0.alphaN` is a pre-release line; expect to bump the
  pin as upstream stabilizes the v1.0 suite.
