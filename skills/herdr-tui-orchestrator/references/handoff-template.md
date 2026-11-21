# Worker Handoff Spec Template (Herdr TUI)

Save each worker's durable spec to `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/tasks/<worker-name>.md`:

```markdown
# Worker Handoff: <worker-name>

- **Worker Agent Name (`herdr`):** `<type>-<topic>` (<= 32 chars, no `/`)
- **Agent Kind & Flags:** `<e.g., --kind pi -- --provider opencode-go --model deepseek-v4.1-flash>`
- **Worktree:** `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/worktrees/<worker-name>`
- **Branch:** `<type>/<topic>` (branched from `<base>` at `<sha>`)
- **Orchestrator Pane / Agent:** `<resolved orchestrator pane ID or agent name>`
- **Report File:** `<state-dir>/reports/<worker-name>.md`

## Objective
<1-3 sentences stating what the worker owns and what "done" looks like.>

## Scope & Boundaries
- **Owned files/dirs:** `<exact paths inside worktree>`
- **Shared/gitignored dependencies:** `<e.g., read-only symlinked .venv / upstream / data, or lockfiles under state dir — never symlink writable output dirs back to main checkout>`
- **Reference assets (if any):** `<paths under ~/.local/state/herdr/<project-slug>/assets/ — read-only, never copy into git>`
- Do **not** modify unrelated files, merge into `<base>`, or spawn sub-agents.

## Reporting and integration
- **Assigned checks and owners:** <include who verifies the combined build and who reports readiness>
- **Expected evidence:** <tested commit/build, command or browser scenario, outcome, log/screenshot path>
- **Notify the orchestrator:** <target above> on progress that changes delivery, blockers, and final results.
- **Notice format:** <worker-name> PROGRESS | BLOCKED | COMPLETE — <scope and revision>, <checks/results>, <evidence>, <pending work and owner or none>.
- **Follow-up or transfer:** Record reopened checks here. Confirm the receiving owner before closing your part.

## Acceptance & Verification Gates
1. `<test / link / lint / metric verification commands>`
2. Clean `git status` in worktree; commits strictly on `<type>/<topic>`.
3. If PR requested: `git fetch origin`, resolve any conflicts vs. `origin/<base>` in worktree, re-verify gates, push, check `gh pr list --head <branch> --state all`, and open/update PR via `gh pr create` (with clear title + concise summary) if `gh auth status` succeeds — otherwise record compare URL + ready-to-paste title & summary.
4. Write verified summary to `<state-dir>/reports/<worker-name>.md` and send the scoped final notice via `herdr agent prompt <orchestrator-agent>`, then stay idle.
```
