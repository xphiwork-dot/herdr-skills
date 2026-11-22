#!/usr/bin/env bash
# herdr-tui-inbox.sh — file-based status inbox for Herdr TUI workers.
#
# Workers write small status files instead of prompting the orchestrator.
# A detached, LLM-free watcher wakes the orchestrator with one line only when
# something needs attention, and `gate` refuses a readiness claim until every
# assigned worker is complete, idle, committed, and reported.
#
# Usage:
#   herdr-tui-inbox.sh init   <state-dir> <orchestrator-target> <worker> [worker ...]
#   herdr-tui-inbox.sh write  <state-dir> <worker> <working|blocked|complete> [options]
#       --summary TEXT        one line, <= 200 chars (also appended to <worker>.log)
#       --check NAME=VALUE    VALUE: pass|pending|fail|baseline|skipped (repeatable, merged)
#       --pending TEXT        outstanding item with owner (repeatable; replaces the list)
#       --needs TEXT          decision or dependency that would unblock you
#       --rev SHA             tested revision (default: HEAD of the current worktree)
#   herdr-tui-inbox.sh reopen <state-dir> <worker> [reason]
#   herdr-tui-inbox.sh read   <state-dir> [--all]
#   herdr-tui-inbox.sh tail   <state-dir> [worker ...] [-n LINES]
#   herdr-tui-inbox.sh watch  <state-dir> [--detach] [--interval SEC] [--stall-min MIN] [--each] [--max-hours H]
#   herdr-tui-inbox.sh stop   <state-dir>
#   herdr-tui-inbox.sh gate   <state-dir> [worker ...]
#
# Files (under <state-dir>/status/): roster.json, <worker>.json (current state),
# <worker>.log (append-only "<state> [at=<epoch>]: <summary>" lines), .cursor.json,
# .watch.pid, .watch.delivered. Watcher log: <state-dir>/logs/inbox-watch.log.
# Requires bash 4+, jq, and git. Harness-agnostic: it only reads `herdr agent get`.
set -euo pipefail

die() { echo "herdr-tui-inbox: $*" >&2; exit 1; }
usage() { sed -n '2,/^# Requires/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

valid_name() {
  [[ $1 =~ ^[a-z0-9][a-z0-9._-]{0,31}$ ]] || die "invalid worker name: $1"
}

atomic_write() {
  local dest=$1 tmp
  tmp=$(mktemp "${dest}.XXXXXX")
  cat >"$tmp"
  mv -f "$tmp" "$dest"
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

roster_workers() {
  local r="$1/status/roster.json"
  [ -f "$r" ] || die "no roster at $r (run init first)"
  jq -r '.workers[]' "$r"
}

roster_orchestrator() { jq -r '.orchestrator' "$1/status/roster.json"; }

# Prints the agent's herdr agent_status, or "missing" if herdr cannot find it.
agent_status() {
  local j
  j=$(herdr agent get "$1" 2>/dev/null) || { echo missing; return; }
  jq -r '.result.agent.agent_status // "unknown"' <<<"$j" 2>/dev/null || echo unknown
}

settled() { case $1 in idle|done) return 0 ;; *) return 1 ;; esac; }

# Appends one human-readable line per status change (tail-friendly).
append_log() {
  local dir=$1 json=$2
  jq -r '"\(.state) [at=\(.at)]\(if (.rev // "") != "" then " rev=" + .rev else "" end): \(.summary // "")\(if .needs then " | needs: " + .needs else "" end)\(if (.pending // []) != [] then " | pending: " + (.pending | join("; ")) else "" end)" | gsub("[\r\n]+"; " ")' \
    <<<"$json" >>"$dir/status/$(jq -r .worker <<<"$json").log"
}

# Emits one problem per line for a status JSON; empty output means ready.
# Pane state is checked separately by `gate`.
status_problems() {
  local dir=$1 json=$2 w st rev wt since rf
  w=$(jq -r '.worker' <<<"$json")
  st=$(jq -r '.state' <<<"$json")
  [ "$st" = complete ] || echo "state=$st"
  jq -r '.pending[]? | "pending: " + .' <<<"$json"
  jq -r '.checks // {} | to_entries[] | select(.value == "pending" or .value == "fail") | "check \(.key)=\(.value)"' <<<"$json"
  jq -r '.needs // empty | "needs: " + .' <<<"$json"
  rev=$(jq -r '.rev // ""' <<<"$json")
  wt=$(jq -r '.worktree // ""' <<<"$json")
  if [ -z "$rev" ]; then
    echo "no tested rev"
  elif [ -n "$wt" ] && [ -d "$wt" ]; then
    local head want
    head=$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)
    want=$(git -C "$wt" rev-parse --verify --quiet "$rev^{commit}" 2>/dev/null || true)
    [ -n "$want" ] && [ "$want" = "$head" ] || echo "rev $rev is not worktree HEAD ${head:0:7}"
    [ -z "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ] || echo "uncommitted tracked changes in $wt"
  fi
  since=$(jq -r '.working_since // 0' <<<"$json")
  rf="$dir/reports/$w.md"
  if [ ! -f "$rf" ]; then
    echo "no report at reports/$w.md"
  elif [ "$(mtime "$rf")" -lt "$since" ]; then
    echo "report older than the current round"
  fi
}

# build_status <dir> <worker> <state> <summary> <needs> <rev> <checks-json> <pending-json|null> [reset]
build_status() {
  local dir=$1 w=$2 state=$3 summary=$4 needs=$5 rev=$6 checks=$7 pending=$8 reset=${9:-0}
  local f="$dir/status/$w.json" prev='{}' top='' now
  [ -f "$f" ] && prev=$(cat "$f")
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$rev" ] && [ -n "$top" ] && [ "$state" != reopened ] && [ "$state" != assigned ]; then
    rev=$(git rev-parse --short HEAD 2>/dev/null || true)
  fi
  now=$(date +%s)
  jq -n --argjson p "$prev" --arg w "$w" --arg s "$state" --arg sum "${summary:0:200}" \
    --arg needs "$needs" --arg rev "$rev" --arg top "$top" --argjson checks "$checks" \
    --argjson pending "$pending" --argjson now "$now" --argjson reset "$reset" '
    ($p.state // "") as $ps
    | {worker: $w, state: $s,
       rev: (if $rev == "" then ($p.rev // "") else $rev end),
       worktree: (if $top == "" or $s == "reopened" then ($p.worktree // "") else $top end),
       checks: ((if $reset == 1 then {} else ($p.checks // {}) end) + $checks),
       pending: (if $pending == null then ($p.pending // []) else $pending end),
       needs: (if $needs == "" then null else $needs end),
       summary: (if $sum == "" then ($p.summary // "") else $sum end),
       seq: (($p.seq // 0) + 1), at: $now,
       working_since: (if $reset == 1 or ($s == "working" and ($ps | IN("working", "blocked") | not))
                       then $now else ($p.working_since // $now) end)}'
}

save_status() {
  local dir=$1 json=$2
  atomic_write "$dir/status/$(jq -r .worker <<<"$json").json" <<<"$json"
  append_log "$dir" "$json"
}

cmd_init() {
  [ $# -ge 3 ] || usage
  local dir=$1 orch=$2 existing='[]' w
  shift 2
  for w in "$@"; do valid_name "$w"; done
  mkdir -p "$dir/status" "$dir/logs" "$dir/reports"
  [ -f "$dir/status/roster.json" ] && existing=$(jq -c '.workers' "$dir/status/roster.json")
  jq -n --arg o "$orch" --argjson e "$existing" '{orchestrator: $o, workers: (($e + $ARGS.positional) | unique)}' \
    --args "$@" | atomic_write "$dir/status/roster.json"
  for w in "$@"; do
    [ -f "$dir/status/$w.json" ] && continue
    save_status "$dir" "$(cd / && build_status "$dir" "$w" assigned "assigned" "" "" '{}' '[]' 1)"
  done
  echo "roster: $(jq -c . "$dir/status/roster.json")"
}

cmd_write() {
  [ $# -ge 3 ] || usage
  local dir=$1 w=$2 state=$3 summary='' needs='' rev='' checks='{}' pending=null k v
  shift 3
  valid_name "$w"
  case $state in working|blocked|complete) ;; *) die "state must be working, blocked or complete";; esac
  [ -d "$dir/status" ] || die "no status dir under $dir (orchestrator runs init)"
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "missing value for $1"
    case $1 in
      --summary) summary=$2 ;;
      --needs) needs=$2 ;;
      --rev) rev=$2 ;;
      --check)
        k=${2%%=*}; v=${2#*=}
        [ "$k" != "$2" ] && [ -n "$k" ] || die "--check needs NAME=VALUE"
        case $v in pass|pending|fail|baseline|skipped) ;; *) die "check value must be pass|pending|fail|baseline|skipped";; esac
        checks=$(jq -c --arg k "$k" --arg v "$v" '.[$k] = $v' <<<"$checks") ;;
      --pending)
        [ "$pending" = null ] && pending='[]'
        pending=$(jq -c --arg p "$2" '. + [$p]' <<<"$pending") ;;
      *) die "unknown option: $1" ;;
    esac
    shift 2
  done
  [ "$state" = complete ] && [ "$pending" = null ] && pending='[]'
  [ "$state" = blocked ] && [ -z "$needs" ] && die "blocked needs --needs \"<what would unblock you>\""
  local json problems
  json=$(build_status "$dir" "$w" "$state" "$summary" "$needs" "$rev" "$checks" "$pending")
  if [ "$state" = complete ]; then
    problems=$(status_problems "$dir" "$json")
    if [ -n "$problems" ]; then
      echo "refusing complete for $w:" >&2
      sed 's/^/  - /' <<<"$problems" >&2
      die "fix these or write working/blocked instead"
    fi
  fi
  save_status "$dir" "$json"
  jq -r '"\(.worker) \(.state) seq=\(.seq) rev=\(.rev)"' <<<"$json"
}

cmd_reopen() {
  [ $# -ge 2 ] || usage
  local dir=$1 w=$2 reason=${3:-follow-up}
  valid_name "$w"
  if ! jq -e --arg w "$w" '.workers | index($w)' "$dir/status/roster.json" >/dev/null 2>&1; then
    cmd_init "$dir" "$(roster_orchestrator "$dir")" "$w" >/dev/null
  fi
  save_status "$dir" "$(cd / && build_status "$dir" "$w" reopened "$reason" "" "" '{}' '[]' 1)"
  echo "$w reopened: $reason"
}

format_line() {
  local json=$1 pane=$2 now
  now=$(date +%s)
  jq -r --arg pane "$pane" --argjson now "$now" '
    def age: ($now - .) as $s | if $s < 90 then "\($s)s" elif $s < 5400 then "\($s / 60 | floor)m" else "\($s / 3600 | floor)h" end;
    [ "\(.worker) \(.state | ascii_upcase) rev=\(if (.rev // "") == "" then "-" else .rev end) pane=\($pane)",
      (if (.checks // {}) == {} then empty else "checks=" + ([.checks | to_entries[] | "\(.key):\(.value)"] | join(",")) end),
      (if (.pending // []) == [] then empty else "pending=" + (.pending | join(" | ")) end),
      (if .needs then "needs=" + .needs else empty end),
      "— \(.summary // "") (\(.at | age) ago)" ] | join(" ")' <<<"$json"
}

cmd_read() {
  [ $# -ge 1 ] || usage
  local dir=$1 all=0 cursor='{}' cf w f json seq cur n=0
  [ "${2:-}" = --all ] && all=1
  cf="$dir/status/.cursor.json"
  [ -f "$cf" ] && cursor=$(cat "$cf")
  while IFS= read -r w; do
    f="$dir/status/$w.json"
    [ -f "$f" ] || { echo "$w (no status file)"; continue; }
    json=$(cat "$f")
    seq=$(jq -r '.seq' <<<"$json")
    cur=$(jq -r --arg w "$w" '.[$w] // -1' <<<"$cursor")
    if [ "$all" = 1 ] || [ "$seq" -gt "$cur" ]; then
      format_line "$json" "$(agent_status "$w")"
      n=$((n + 1))
    fi
    cursor=$(jq -c --arg w "$w" --argjson s "$seq" '.[$w] = $s' <<<"$cursor")
  done < <(roster_workers "$dir")
  atomic_write "$cf" <<<"$cursor"
  [ "$n" -gt 0 ] || echo "no changes"
}

cmd_tail() {
  [ $# -ge 1 ] || usage
  local dir=$1 lines=3 workers=() w
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      -n) lines=${2:?}; shift 2 ;;
      *) workers+=("$1"); shift ;;
    esac
  done
  [ "${#workers[@]}" -gt 0 ] || mapfile -t workers < <(roster_workers "$dir")
  for w in "${workers[@]}"; do
    echo "== $w"
    if [ -f "$dir/status/$w.log" ]; then
      tail -n "$lines" "$dir/status/$w.log" | cut -c1-300
    else
      echo "(no log)"
    fi
  done
}

cmd_stop() {
  [ $# -ge 1 ] || usage
  local pf="$1/status/.watch.pid" pid
  [ -f "$pf" ] || { echo "no watcher"; return; }
  pid=$(cat "$pf")
  if kill "$pid" 2>/dev/null; then echo "stopped watcher $pid"; else echo "watcher $pid not running"; fi
  rm -f "$pf"
}

cmd_watch() {
  [ $# -ge 1 ] || usage
  local dir=$1 interval=15 stall=20 each=0 detach=0 maxh=24
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      --detach) detach=1; shift ;;
      --each) each=1; shift ;;
      --interval) interval=${2:?}; shift 2 ;;
      --stall-min) stall=${2:?}; shift 2 ;;
      --max-hours) maxh=${2:?}; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -f "$dir/status/roster.json" ] || die "no roster (run init first)"
  local log="$dir/logs/inbox-watch.log"
  mkdir -p "$dir/logs"
  if [ "$detach" = 1 ]; then
    local args=(watch "$dir" --interval "$interval" --stall-min "$stall" --max-hours "$maxh")
    [ "$each" = 1 ] && args+=(--each)
    # Closed FDs + new session: the caller's turn (omp, codex, claude, pi, agy) returns at once.
    nohup setsid bash "$0" "${args[@]}" </dev/null >>"$log" 2>&1 &
    echo "watcher started (pid $!, log $log)"
    return
  fi

  local pf="$dir/status/.watch.pid" dl="$dir/status/.watch.delivered" old
  if [ -f "$pf" ]; then
    old=$(cat "$pf")
    if [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then kill "$old" 2>/dev/null || true; fi
  fi
  echo "$$" >"$pf"
  trap '[ "$(cat "'"$pf"'" 2>/dev/null)" = "'"$$"'" ] && rm -f "'"$pf"'"' EXIT
  touch "$dl"
  logp() { printf '%s %s\n' "$(date -Iseconds 2>/dev/null || date)" "$*"; }
  logp "watching $dir (interval ${interval}s, stall ${stall}m, each=$each)"

  declare -A idle_since=() pane_prev=() queued=()
  local order=() deadline=$(( $(date +%s) + maxh * 3600 ))
  local orch w f json st seq needs a now all key msg sig nworkers

  enqueue() {
    grep -qxF "$1" "$dl" && return 0
    [ -n "${queued[$1]+x}" ] && return 0
    queued[$1]=$2
    order+=("$1")
    logp "queued: $2"
  }

  while :; do
    now=$(date +%s)
    [ "$now" -lt "$deadline" ] || { logp "max lifetime reached; exiting"; exit 0; }
    orch=$(roster_orchestrator "$dir")
    all=1; sig=''; nworkers=0
    while IFS= read -r w; do
      nworkers=$((nworkers + 1))
      f="$dir/status/$w.json"
      [ -f "$f" ] || { all=0; continue; }
      json=$(cat "$f")
      st=$(jq -r '.state' <<<"$json")
      seq=$(jq -r '.seq' <<<"$json")
      needs=$(jq -r '.needs // ""' <<<"$json")
      a=$(agent_status "$w")
      sig+="$w:$seq;"
      # A pane held on a permission or trust prompt for two ticks.
      if [ "$a" = blocked ] && [ "${pane_prev[$w]:-}" = blocked ]; then
        enqueue "pane-blocked:$w:$seq" "$w pane is waiting for input (permission prompt?)"
      fi
      pane_prev[$w]=$a
      [ -n "$needs" ] && enqueue "needs:$w:$seq" "$w ${st^^} needs: $needs"
      if [ "$st" = complete ]; then
        if settled "$a"; then
          [ "$each" = 1 ] && enqueue "complete:$w:$seq" "$w COMPLETE rev=$(jq -r '.rev' <<<"$json")"
        else
          all=0  # Status says complete but the agent is still doing more: not done, no wake.
        fi
        unset "idle_since[$w]"
        continue
      fi
      all=0
      if settled "$a" || [ "$a" = missing ]; then
        idle_since[$w]=${idle_since[$w]:-$now}
        if [ $(( now - idle_since[$w] )) -ge $(( stall * 60 )) ]; then
          if [ "$a" = missing ]; then
            enqueue "missing:$w:$seq" "$w agent not found but status=$st"
          else
            enqueue "stall:$w:$seq" "$w idle ${stall}m+ but status=$st (stalled, interrupted, or forgot to write status)"
          fi
        fi
      else
        unset "idle_since[$w]"
      fi
    done < <(roster_workers "$dir")

    if [ "$all" = 1 ] && [ "$nworkers" -gt 0 ]; then
      enqueue "all:$sig" "all $nworkers worker(s) COMPLETE and idle; run gate"
    fi

    if [ "${#order[@]}" -gt 0 ]; then
      a=$(agent_status "$orch")
      if settled "$a"; then
        msg=''
        for key in "${order[@]}"; do msg+="${msg:+; }${queued[$key]}"; done
        msg="[herdr-inbox] ${#order[@]} update(s): ${msg:0:600}. Run: $0 read $dir"
        if herdr agent prompt "$orch" "$msg" >/dev/null 2>&1; then
          printf '%s\n' "${order[@]}" >>"$dl"
          logp "woke $orch: $msg"
          queued=(); order=()
        else
          logp "prompt to $orch failed; will retry"
        fi
      fi
    fi

    if [ "$all" = 1 ] && grep -qxF "all:$sig" "$dl"; then
      logp "all workers settled and delivered; exiting"
      exit 0
    fi
    sleep "$interval"
  done
}

cmd_gate() {
  [ $# -ge 1 ] || usage
  local dir=$1 rc=0 w f json problems a
  shift
  local workers=("$@")
  [ "${#workers[@]}" -gt 0 ] || mapfile -t workers < <(roster_workers "$dir")
  [ "${#workers[@]}" -gt 0 ] || die "no workers to gate"
  for w in "${workers[@]}"; do
    f="$dir/status/$w.json"
    if [ ! -f "$f" ]; then echo "FAIL $w: no status file"; rc=1; continue; fi
    json=$(cat "$f")
    problems=$(status_problems "$dir" "$json")
    a=$(agent_status "$w")
    settled "$a" || problems+="${problems:+$'\n'}agent is $a (still running or unreachable)"
    if [ -z "$problems" ]; then
      echo "OK   $w rev=$(jq -r '.rev' <<<"$json")"
    else
      echo "FAIL $w: $(paste -sd ';' <<<"$problems" | sed 's/;/; /g')"
      rc=1
    fi
  done
  if [ "$rc" = 0 ]; then
    echo "gate: ready (${#workers[@]} worker(s))"
  else
    echo "gate: NOT ready — ask the failing workers what remains"
  fi
  return "$rc"
}

main() {
  [ $# -ge 1 ] || usage
  local cmd=$1
  shift
  case $cmd in
    init) cmd_init "$@" ;;
    write) cmd_write "$@" ;;
    reopen) cmd_reopen "$@" ;;
    read) cmd_read "$@" ;;
    tail) cmd_tail "$@" ;;
    watch) cmd_watch "$@" ;;
    stop) cmd_stop "$@" ;;
    gate) cmd_gate "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
