# A2A TCK Compliance

We measure how well agents built with this SDK conform to the A2A v1.0 spec
using the official [a2a-tck](https://github.com/a2aproject/a2a-tck) suite.

**Status:** we are not compliant yet — this is expected. CI reports the result
on every build without failing the build.

## What gets tested

The **System Under Test (SUT)** is the `examples/compliance_server` agent,
served over both the JSON-RPC and HTTP+JSON bindings on port 5002. The TCK
fetches its agent card from `/.well-known/agent-card.json` and runs a pytest
suite classified by RFC 2119 level (MUST / SHOULD / MAY).

That example exists so the score reflects the *library*. The TCK signals the
behaviour it wants in-band, through the request's `messageId` prefix, and gates
whole test classes on advertised capabilities — so an agent that ignores those
prefixes or under-reports its capabilities scores far below what the SDK can
actually do. `examples/compliance_server` implements the full prefix contract
and advertises streaming and push; see its README.

Override the SUT with
`SUT_DIR=examples/echo_server SUT_PORT=5001 scripts/run_tck.sh` to measure the
minimal example instead — the echo server's port is hard-coded to 5001, so
`SUT_PORT` has to move with `SUT_DIR`.

> Use `examples/echo_server` as the readable "how do I write an agent" example.
> Use `examples/compliance_server` for compliance measurement.

## Pinned TCK version

```
TCK_REF = 1.0.0.alpha2
```

This is the most recent v1.0-line TCK tag with JSON-RPC support. Bumping it means
updating this line **and** the `compliance` job in `.github/workflows/ci.yml`
together, then re-cloning.

## One-time bootstrap

Prerequisites: Python 3.11+, git, curl, jq, and the Elixir toolchain (this repo).

Install `uv` (the TCK uses it):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# then ensure the printed install dir (usually ~/.local/bin) is on your PATH
export PATH="$HOME/.local/bin:$PATH"
```

Check out and install the TCK as a **sibling** of this repo:

```bash
cd ..                      # parent of the a2a_sdk_ex checkout
git clone --branch 1.0.0.alpha2 https://github.com/a2aproject/a2a-tck.git a2a-tck
cd a2a-tck
uv venv
uv pip install -e .
```

You now have `../a2a-tck` next to `a2a_sdk_ex`. `scripts/run_tck.sh` expects it
there (override with `TCK_DIR`).

## Running the harness

From the repo root:

```bash
mix deps.get
(cd examples/compliance_server && mix deps.get)
scripts/run_tck.sh
```

Reports land in `reports/` (git-ignored): `compatibility.json` (machine-readable),
`compatibility.html` and `tck_report.html` (human-readable), `junitreport.xml`.

Open `reports/compatibility.html` for the summary and per-requirement breakdown.

## CI

The `compliance` job in CI runs this same script on every build and uploads
`reports/` as a downloadable artifact named `tck-compliance-report`.

It is **report-only**: TCK non-compliance keeps the job **green** (we are not
compliant yet and don't want a red ✗ on the PR). The job only turns **red** if
the harness itself breaks — i.e. `run_tck.sh` exits `2`/`3`/`4` (TCK checkout
missing, the SUT won't boot, or it never becomes ready) — because those are
real, actionable failures rather than "we're still working towards compliance".
