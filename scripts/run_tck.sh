#!/usr/bin/env bash
#
# Run the A2A TCK compliance suite against the echo-server example.
#
# The TCK itself is a PRE-PROVIDED dependency: this script does not clone or
# install it. It expects a checkout at $TCK_DIR (default ../a2a-tck). See
# docs/tck-compliance.md for the one-time bootstrap.
#
# Config (env vars, all optional):
#   TCK_DIR        Sibling TCK checkout            (default: ../a2a-tck)
#   SUT_PORT       Echo server port               (default: 5001)
#   SUT_HOST       Base URL passed to the TCK      (default: http://localhost:$SUT_PORT)
#   REPORTS_DIR    Where reports are collected     (default: reports)
#   READY_TIMEOUT  Seconds to wait for readiness   (default: 30)
#
# Exit codes: 2 = TCK missing, 3 = server failed to boot, 4 = never ready,
#             otherwise the TCK's own exit code.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TCK_DIR="${TCK_DIR:-$REPO_ROOT/../a2a-tck}"
SUT_PORT="${SUT_PORT:-5001}"
SUT_HOST="${SUT_HOST:-http://localhost:$SUT_PORT}"
REPORTS_DIR="${REPORTS_DIR:-$REPO_ROOT/reports}"
READY_TIMEOUT="${READY_TIMEOUT:-30}"

log() { printf '[run_tck] %s\n' "$*" >&2; }
die() { log "ERROR: $2"; exit "$1"; }

# --- Assert the TCK dependency is present (fully agnostic about its ref) ------
{ [ -d "$TCK_DIR" ] && [ -f "$TCK_DIR/run_tck.py" ]; } || die 2 \
  "a2a-tck not found at '$TCK_DIR' (no run_tck.py). Check it out first — see docs/tck-compliance.md."

log "Using TCK at: $TCK_DIR"
log "SUT: $SUT_HOST"
log "Reports: $REPORTS_DIR"

# (server boot / readiness / run / teardown added in Task 3)
