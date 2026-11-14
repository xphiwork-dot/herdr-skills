#!/usr/bin/env sh
# Detached Herdr (hc) watchdog helper.
# Usage:
#   hc run --bg --rm --no-notify --name watch-workers \
#     /path/to/herdr-watch.sh "$HC_TERMINAL_ID" "/path/to/watch.log" worker1 [worker2 ...]

set -eu

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <orchestrator-id> <log-file> <target-terminal> [target-terminal ...]" >&2
  exit 2
fi

ORCH="$1"
LOG_FILE="$2"
shift 2

mkdir -p "$(dirname "$LOG_FILE")"
log() {
  printf '%s [herdr-watch -> %s] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$ORCH" "$*" >>"$LOG_FILE"
}

log "started watching: $*"

# Brief settle delay so a worker just given a new turn via `hc send` from $ORCH
# transitions from previous `done`/`idle` into `working` before this separate terminal waits on it.
sleep 3

for target in "$@"; do
  while :; do
    out="$(hc wait --json "$target" --timeout 180 2>/dev/null || printf '{"ended":true,"reason":"not_found"}')"
    case "$out" in
      *'"ended":true'*)
        log "settled: $target ($out)"
        break
        ;;
    esac
  done
done

# Give the final worker a moment to deliver its own `hc send $ORCH` report first.
sleep 3

orch_json="$(hc get --json "$ORCH" 2>/dev/null || true)"
case "$orch_json" in
  *'"status":"working"'*)
    log "skipped nudge: orchestrator $ORCH is already working (worker push or user chat active)"
    exit 0
    ;;
  *'"status":"blocked"'*)
    log "skipped nudge: orchestrator $ORCH is blocked"
    exit 0
    ;;
esac

# Note: Do NOT pass `--if idle` here! After turn 1+, coding agents (omp, pi, claude, agy, codex)
# report OSC 7501 status `done` rather than `idle`, and `--if idle` fails with exit 10 on `done`.
if hc send "$ORCH" "[herdr-watch] watched target(s) settled ($*); check hc ls / reports" >/dev/null 2>&1; then
  log "nudged orchestrator $ORCH"
else
  log "hc send to $ORCH returned nonzero (orchestrator may have exited)"
fi
