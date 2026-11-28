#!/usr/bin/env bash
set -eu
resolver=$(cd "$(dirname "$0")/.." && pwd)/skills/herdr-tui-orchestrator/scripts/herdr-tui-context.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export CODEX_HOME=$tmp CODEX_THREAD_ID=test-thread PATH="$tmp:$PATH"
unset HERDR_PANE_ID
cd "$tmp"
echo '{"id":"test-thread","thread_name":"Review labels"}' > session_index.jsonl
cat > herdr <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  'agent list') cat agents.json ;;
  'pane get') jq -n --arg pane "$3" '{result:{pane:{pane_id:$pane,workspace_id:"ws"}}}' ;;
  *) exit 1 ;;
esac
MOCK
chmod +x herdr
jq -n --arg dir "$PWD" --arg title "⠇ Review labels | ${PWD##*/}" '{result:{agents:[{agent:"codex",pane_id:"p1",foreground_cwd:$dir,terminal_title_stripped:$title}]}}' > agents.json
"$resolver" | jq -e '.pane_id == "p1"' >/dev/null
jq '.result.agents += [(.result.agents[0] | .pane_id="p2")]' agents.json > next && mv next agents.json
if "$resolver" >/dev/null 2>&1; then exit 1; fi
jq '.result.agents[1].agent_session={kind:"id",value:"test-thread"}' agents.json > next && mv next agents.json
"$resolver" | jq -e '.pane_id == "p2"' >/dev/null
