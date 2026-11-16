#!/usr/bin/env bash
# herdr-tui-spawn.sh — provision a worker shell as a child workspace ("subtree")
# nested directly under the orchestrator's workspace in the Herdr TUI sidebar.
#
# Usage: herdr-tui-spawn.sh <worker-name> <cwd> [parent-workspace-id]
#
#   1. `herdr workspace create --no-focus` with label "└ <worker-name>"
#   2. Reorders it right after the parent workspace (after any existing "└ "
#      siblings) via the raw-socket `workspace.move` request — the CLI has no
#      `workspace move` subcommand. Ordering is cosmetic: on failure the worker
#      still runs, just at the end of the sidebar (a warning goes to stderr).
#   3. Prints JSON: {"workspace_id","tab_id","pane_id","label","moved"}
#
# Parent defaults to $HERDR_WORKSPACE_ID. Socket: $HERDR_SOCKET_PATH or
# ${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock. Requires jq + python3.
set -euo pipefail

name=${1:?usage: herdr-tui-spawn.sh <worker-name> <cwd> [parent-workspace-id]}
cwd=${2:?usage: herdr-tui-spawn.sh <worker-name> <cwd> [parent-workspace-id]}
parent=${3:-${HERDR_WORKSPACE_ID:-}}
socket=${HERDR_SOCKET_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock}
label="└ $name"

[ -d "$cwd" ] || { echo "error: cwd not found: $cwd" >&2; exit 2; }

created=$(herdr workspace create --cwd "$cwd" --label "$label" --no-focus)
ws=$(printf '%s' "$created" | jq -er '.result.workspace.workspace_id // .result.root_pane.workspace_id')
pane=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id')
tab=$(printf '%s' "$created" | jq -r '.result.root_pane.tab_id // .result.tab.tab_id // empty')

moved=false
if [ -z "$parent" ]; then
  echo "warning: no parent workspace (\$HERDR_WORKSPACE_ID unset); left at end of sidebar" >&2
else
  # Target index: just past the parent and its contiguous "└ " children.
  desired=$(herdr workspace list | jq -r --arg p "$parent" --arg ws "$ws" '
    [.result.workspaces[] | select(.workspace_id != $ws)] as $l
    | ($l | map(.workspace_id) | index($p)) as $i
    | if $i == null then empty else
        ($i + 1) as $start
        | ([range($start; $l | length)]
           | map(select(($l[.].label // "") | startswith("└ ") | not)) | first) // ($l | length)
      end')
  if [ -z "$desired" ]; then
    echo "warning: parent workspace $parent not found; left at end of sidebar" >&2
  elif python3 - "$socket" "$ws" "$desired" <<'PY'
import json, socket, sys
path, ws, idx = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(path)
req = {"id": "herdr-tui-spawn", "method": "workspace.move",
       "params": {"workspace_id": ws, "insert_index": idx}}
s.sendall((json.dumps(req) + "\n").encode())
buf = b""
while b"\n" not in buf:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
resp = json.loads(buf.split(b"\n", 1)[0] or b"{}")
sys.exit(0 if resp.get("error") is None and isinstance(resp.get("result"), dict) else 1)
PY
  then
    moved=true
  else
    echo "warning: workspace.move failed (needs herdr protocol >= 16); left at end of sidebar" >&2
  fi
fi

jq -n --arg ws "$ws" --arg tab "$tab" --arg pane "$pane" --arg lbl "$label" --argjson moved "$moved" \
  '{workspace_id: $ws, tab_id: $tab, pane_id: $pane, label: $lbl, moved: $moved}'
