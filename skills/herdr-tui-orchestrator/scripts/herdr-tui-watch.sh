#!/usr/bin/env sh
# Detached Herdr TUI (`herdr`) watchdog helper.
# Launch detached with closed FDs:
#   nohup setsid /path/to/herdr-tui-watch.sh "<orchestrator-agent>" "/path/to/watch.log" worker1 [worker2 ...] </dev/null >/dev/null 2>&1 &

set -eu

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <orchestrator-agent> <log-file> <worker-agent> [worker-agent ...]" >&2
  exit 2
fi

ORCH="$1"
LOG_FILE="$2"
shift 2

mkdir -p "$(dirname "$LOG_FILE")"
log() {
  printf '%s [herdr-tui-watch -> %s] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$ORCH" "$*" >>"$LOG_FILE"
}

log "started watching: $*"
sleep 3

for target in "$@"; do
  herdr agent wait "$target" >/dev/null 2>&1 || true
  log "settled: $target"
done

sleep 3

orch_json="$(herdr agent get "$ORCH" 2>/dev/null || true)"
case "$orch_json" in
  *'"working"'*|*'"blocked"'*)
    log "skipped nudge: orchestrator $ORCH is already working or blocked"
    exit 0
    ;;
esac

if herdr agent prompt "$ORCH" "[herdr-watch] watched worker(s) settled ($*); check herdr agent list / reports" >/dev/null 2>&1; then
  log "nudged orchestrator $ORCH"
else
  log "herdr agent prompt to $ORCH returned nonzero"
fi
