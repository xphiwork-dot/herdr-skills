#!/usr/bin/env bash
# Run with: bash tests/herdr-tui-inbox-test.sh
# Requires Bash, git, jq and GNU timeout. No Herdr daemon is used.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
inbox="$repo/skills/herdr-tui-orchestrator/scripts/herdr-tui-inbox.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
worktree="$tmp/worktree"
state="$tmp/inbox"
mkdir -p "$tmp/bin" "$worktree"

export MOCK_PROMPTS="$tmp/prompts" MOCK_TICKS="$tmp/ticks"
export PATH="$tmp/bin:$PATH"
cat > "$tmp/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1:$2:$3" in
  agent:get:worker)
    ticks=$(cat "$MOCK_TICKS")
    printf '%s\n' "$((ticks + 1))" > "$MOCK_TICKS"
    if (( ticks < ${MOCK_MISSING_POLLS:-0} )); then exit 1; fi
    printf '%s\n' '{"result":{"agent":{"agent_status":"done"}}}'
    ;;
  agent:get:orchestrator)
    printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}'
    ;;
  agent:prompt:orchestrator) printf '%s\n' "$4" >> "$MOCK_PROMPTS";;
  *) exit 2;;
esac
MOCK
chmod +x "$tmp/bin/herdr"
printf '0\n' > "$MOCK_TICKS"
: > "$MOCK_PROMPTS"

git -C "$worktree" init -q
git -C "$worktree" config user.name 'Inbox test'
git -C "$worktree" config user.email 'inbox-test@example.invalid'
git -C "$worktree" config commit.gpgsign false
git -C "$worktree" -c core.hooksPath=/dev/null commit -qm fixture --allow-empty
bash "$inbox" init "$state" orchestrator worker
(
  cd "$worktree"
  bash "$inbox" write "$state" worker working
  printf 'Test report\n' > "$state/reports/worker.md"
  bash "$inbox" write "$state" worker complete --check smoke=pass
)
bash "$inbox" gate "$state"

expect_gate_failure() {
  local label=$1 pattern=$2 output
  if output=$(bash "$inbox" gate "$state" 2>&1); then
    printf 'FAIL: gate accepted %s\n%s\n' "$label" "$output" >&2
    exit 1
  fi
  if ! grep -qiF "$pattern" <<<"$output"; then
    printf 'FAIL: gate did not explain %s\n%s\n' "$label" "$output" >&2
    exit 1
  fi
}

mv "$worktree" "$worktree.moved"
expect_gate_failure 'a missing worktree path' 'worktree'
mv "$worktree.moved" "$worktree"

status="$state/status/worker.json"
cp "$status" "$tmp/status.json"
jq 'del(.worktree)' "$tmp/status.json" > "$status"
expect_gate_failure 'an unrecorded worktree' 'worktree'
cp "$tmp/status.json" "$status"
bash "$inbox" gate "$state"

# Simulate loss after the worker wrote its report, then reconnect it. More than
# one missing poll checks that the warning is deduplicated for the same status.
printf '0\n' > "$MOCK_TICKS"
MOCK_MISSING_POLLS=3 timeout 10s bash "$inbox" watch "$state" --interval 0.1 --stall-min 0
mapfile -t prompts < "$MOCK_PROMPTS"
if [[ ${#prompts[@]} != 2 || ${prompts[0]} != *"agent not found"* || ${prompts[0]} == *"all 1 worker"* || ${prompts[1]} != *"all 1 worker"* ]]; then
  printf 'FAIL: expected one missing warning then one all-complete wake\n' >&2
  cat "$MOCK_PROMPTS" >&2
  exit 1
fi

git -C "$worktree" -c core.hooksPath=/dev/null commit -qm advance --allow-empty
expect_gate_failure 'a different HEAD' 'not worktree HEAD'
printf 'PASS: Herdr inbox gate and watcher regressions\n'
