#!/usr/bin/env bash
#
# Run the A2A TCK compliance suite against the compliance-server example.
#
# The TCK itself is a PRE-PROVIDED dependency: this script does not clone or
# install it. It expects a checkout at $TCK_DIR (default ../a2a-tck). See
# docs/tck-compliance.md for the one-time bootstrap.
#
# Config (env vars, all optional):
#   TCK_DIR        Sibling TCK checkout            (default: ../a2a-tck)
#   SUT_DIR        Example app to run as the SUT  (default: examples/compliance_server)
#   SUT_PORT       SUT port                       (default: 5002)
#   SUT_HOST       Base URL passed to the TCK      (default: http://localhost:$SUT_PORT)
#   REPORTS_DIR    Where reports are collected     (default: reports)
#   READY_TIMEOUT  Seconds to wait for readiness   (default: 30)
#
# Exit codes: 2 = TCK missing, 3 = server failed to boot, 4 = never ready,
#             otherwise the TCK's own exit code.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TCK_DIR="${TCK_DIR:-$REPO_ROOT/../a2a-tck}"
SUT_DIR="${SUT_DIR:-$REPO_ROOT/examples/compliance_server}"
SUT_PORT="${SUT_PORT:-5002}"
SUT_HOST="${SUT_HOST:-http://localhost:$SUT_PORT}"
REPORTS_DIR="${REPORTS_DIR:-$REPO_ROOT/reports}"
READY_TIMEOUT="${READY_TIMEOUT:-30}"

log() { printf '[run_tck] %s\n' "$*" >&2; }
die() { log "ERROR: $2"; exit "$1"; }

# --- Assert the TCK dependency is present (fully agnostic about its ref) ------
{ [ -d "$TCK_DIR" ] && [ -f "$TCK_DIR/run_tck.py" ]; } || die 2 \
  "a2a-tck not found at '$TCK_DIR' (no run_tck.py). Check it out first — see docs/tck-compliance.md."

log "Using TCK at: $TCK_DIR"
log "SUT: $SUT_HOST ($SUT_DIR)"
log "Reports: $REPORTS_DIR"

# --- Boot the SUT in the background ----------------------------------------
# `exec mix run` inside the subshell replaces it, so $! is the beam.smp PID.
# beam puts itself in its own process group, so the negative-PID kill in
# cleanup() takes the whole tree (incl. erl_child_setup) without touching us.
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    log "Stopping SUT (pid $SERVER_PID)"
    kill -TERM "-$SERVER_PID" 2>/dev/null || kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

log "Booting SUT on port $SUT_PORT ..."
( cd "$SUT_DIR" && exec mix run --no-halt ) \
  >/tmp/a2a_sut.log 2>&1 &
SERVER_PID=$!
kill -0 "$SERVER_PID" 2>/dev/null || die 3 "SUT process did not start (see /tmp/a2a_sut.log)"

# --- Wait for readiness (poll the agent card) ------------------------------
card_url="$SUT_HOST/.well-known/agent-card.json"
log "Waiting up to ${READY_TIMEOUT}s for $card_url ..."
ready=""
for _ in $(seq 1 "$READY_TIMEOUT"); do
  if curl -fsS -o /dev/null "$card_url" 2>/dev/null; then ready=1; break; fi
  kill -0 "$SERVER_PID" 2>/dev/null || die 3 "SUT exited during startup (see /tmp/a2a_sut.log)"
  sleep 1
done
[ -n "$ready" ] || die 4 "SUT never became ready at $card_url within ${READY_TIMEOUT}s"
log "SUT is ready."

# --- Run the TCK -----------------------------------------------------------
mkdir -p "$REPORTS_DIR"
log "Running TCK against $SUT_HOST ..."
tck_status=0
( cd "$TCK_DIR" && uv run ./run_tck.py --sut-host "$SUT_HOST" ) || tck_status=$?

# --- Collect reports -------------------------------------------------------
if [ -d "$TCK_DIR/reports" ]; then
  cp -R "$TCK_DIR/reports/." "$REPORTS_DIR/" 2>/dev/null || true
  log "Reports collected in $REPORTS_DIR"
else
  log "WARNING: TCK produced no reports/ directory"
fi

log "TCK exit status: $tck_status"
exit "$tck_status"
