# Worker Handoff Spec Template (Herdr TUI)

Save each worker's durable spec to `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/tasks/<worker-name>.md`:

```markdown
# Worker Handoff: <worker-name>

- **Worker Agent Name (`herdr`):** `<type>-<topic>` (<= 32 chars, no `/`)
- **Agent Kind & Flags:** `<e.g., --kind pi -- --provider opencode-go --model deepseek-v4.1-flash>`
- **Worktree:** `<abs-path-to-worktree>`
- **Branch:** `<type>/<topic>` (branched from `<base>` at `<sha>`)
- **Orchestrator Pane / Agent:** `<$HERDR_PANE_ID or orchestrator agent name>`
- **Report File:** `<state-dir>/reports/<worker-name>.md`

## Objective
<1-3 sentences stating what the worker owns and what "done" looks like.>

## Scope & Boundaries
- **Owned files/dirs:** `<exact paths>`
- **Shared/gitignored dependencies:** `<e.g., symlinked .venv / upstream / data, or lockfiles under state dir>`
- **Reference assets (if any):** `<paths under ~/.local/state/herdr/<project-slug>/assets/ — read-only, never copy into git>`
- Do **not** modify unrelated files, merge into `<base>`, or spawn sub-agents.

## Acceptance & Verification Gates
1. `<test / link / lint / metric verification commands>`
2. Clean `git status` in worktree; commits strictly on `<type>/<topic>`.
3. If PR requested: `git fetch origin`, resolve any conflicts vs. `origin/<base>` in worktree, re-verify gates, push, check `gh pr list --head <branch> --state all`, and open/update PR via `gh pr create` (with clear title + concise summary) if `gh auth status` succeeds — otherwise record compare URL + ready-to-paste title & summary.
4. Write verified summary to `<state-dir>/reports/<worker-name>.md` (and send via `herdr agent prompt <orchestrator-agent>` if requested), then stay idle.
```
