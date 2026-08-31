# A2A TCK Compliance

We measure how well agents built with this SDK conform to the A2A v1.0 spec
using the official [a2a-tck](https://github.com/a2aproject/a2a-tck) suite.

**Status:** we are not compliant yet — this is expected. CI reports the result
on every build without failing the build.

## What gets tested

The **System Under Test (SUT)** is the `examples/echo_server` agent, served over
the JSON-RPC binding on port 5001. The TCK fetches its agent card from
`/.well-known/agent-card.json` and runs a pytest suite classified by RFC 2119
level (MUST / SHOULD / MAY).

> The echo server is intentionally minimal, so the score reflects the *example*,
> not the library's full capability. A dedicated conformance-fixture agent is a
> planned follow-up.

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
(cd examples/echo_server && mix deps.get)
scripts/run_tck.sh
```

Reports land in `reports/` (git-ignored): `compatibility.json` (machine-readable),
`compatibility.html` and `tck_report.html` (human-readable), `junitreport.xml`.

Open `reports/compatibility.html` for the summary and per-requirement breakdown.

## CI

The `compliance` job in CI runs this same script on every build, is non-blocking
(`continue-on-error`), and uploads `reports/` as a downloadable artifact named
`tck-compliance-report`.
