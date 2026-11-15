# Worker Handoff Spec Template

Save each worker's durable spec to `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/tasks/<worker-name>.md`:

```markdown
# Worker Handoff: <worker-name>

- **Worker Name (`hc`):** `<type>-<topic>` (<= 32 chars, no `/`)
- **Agent Command:** `<e.g., pi --provider opencode-go --model deepseek-v4.1-flash>`
- **Worktree:** `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/worktrees/<worker-name>`
- **Branch:** `<type>/<topic>` (branched from `<base>` at `<sha>`)
- **Orchestrator Terminal:** `<$HC_TERMINAL_ID>`

## Objective
<1-3 sentences stating what the worker owns and what "done" looks like.>

## Scope & Boundaries
- **Owned files/dirs:** `<exact paths inside worktree>`
- **Shared/gitignored dependencies:** `<e.g., read-only symlinked .venv / upstream / data, or lockfiles under state dir — never symlink writable output dirs back to main checkout>`
- **Reference assets (if any):** `<paths under ~/.local/state/herdr/<project-slug>/assets/ — read-only, never copy into git>`
- Do **not** modify unrelated files, merge into `<base>`, or spawn sub-agents.

## Acceptance & Verification Gates
1. `<test / link / lint / metric verification commands>`
2. Clean `git status` in worktree; commits strictly on `<type>/<topic>`.
3. If PR requested: `git fetch origin`, resolve any conflicts vs. `origin/<base>` in worktree, re-verify gates, push, check `gh pr list --head <branch> --state all`, and open/update PR via `gh pr create` (with clear title + concise summary) if `gh auth status` succeeds — otherwise report compare URL + ready-to-paste title & summary.
4. Report via `hc send <$HC_TERMINAL_ID> "<concise verified summary>"` and stay idle.
```
