#!/usr/bin/env bash
# Resolve the orchestrator pane and workspace without relying on UI focus.
set -euo pipefail

pane=${1:-}
thread=${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}
if [[ -z "$pane" && -n "$thread" ]]; then
  agents=$(herdr agent list)
  pane=$(jq -r --arg thread "$thread" '
    [.result.agents[] | select(.agent == "codex"
      and .agent_session.kind == "id" and .agent_session.value == $thread) | .pane_id]
    | unique | if length > 1 then error("Codex thread matches multiple Herdr panes")
      else .[0] // empty end' <<< "$agents")
fi

pane=${pane:-${HERDR_PANE_ID:-}}
# Shared-daemon Codex panes may omit agent_session but display the thread title.
index=${CODEX_HOME:-$HOME/.codex}/session_index.jsonl
if [[ -z "$pane" && -n "$thread" && -r "$index" ]]; then
  title=$(jq -rs --arg id "$thread" '[.[] | select(.id == $id) | .thread_name] | last // empty' "$index")
  if [[ -n "$title" ]]; then
    pane=$(jq -r --arg dir "$PWD" --arg title "$title | ${PWD##*/}" '
      [.result.agents[] | select(.agent == "codex" and .agent_session == null
        and .foreground_cwd == $dir and ((.terminal_title_stripped // "")
        | sub("^[^[:alnum:][:space:]]+ "; "") == $title or . == $title)) | .pane_id] | unique
      | if length == 1 then .[0] else empty end' <<< "$agents")
  fi
fi
if [[ -z "$pane" ]]; then
  echo 'Cannot identify the orchestrator pane. Restart Codex with --no-daemon from Herdr or pass a pane ID confirmed by the user.' >&2
  exit 1
fi

result=$(herdr pane get "$pane")
jq -ce --arg pane "$pane" '
  .result.pane | select(.pane_id == $pane and (.workspace_id | type == "string" and length > 0))
  | {pane_id, workspace_id}' <<< "$result"
