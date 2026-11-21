---
name: herdr-tui-worker
description: >-
  Execute a bounded assignment as a Herdr TUI orchestration worker (`herdr` CLI /
  `HERDR_PANE_ID`). Use only when the assigning agent or user explicitly
  specifies the herdr-tui-worker skill; do not activate automatically.
---

# Herdr TUI Worker (`herdr` CLI)

Activate only when the assigning agent or user explicitly specifies `herdr-tui-worker`. Follow higher-priority host rules and the assignment; this skill grants no extra permissions.

## Worker Rules

1. **Stay strictly within your centralized worktree and assigned boundaries.**
   - Read the full handoff spec (under `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/tasks/<worker-name>.md` or the path in your prompt), relevant repo docs/code, and any referenced screenshots under `.../assets/` before editing.
   - Verify your working directory (`git rev-parse --show-toplevel` and `git branch --show-current`) matches your assigned centralized worktree (`${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/worktrees/<worker-name>`) and branch (`<type>/<topic>`). **Never** write to or modify the user's main checkout, sibling worktrees under `.../worktrees/`, or writable symlinks pointing back into the main checkout.
   - Keep scratch files, logs, lockfiles, reports, and reference screenshots inside `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/{logs,locks,reports,assets}/` (or `/tmp`)—**never** copy reference screenshots or temp artifacts into your git worktree unless explicitly instructed.
   - Edit only your owned files inside your assigned worktree. Flag missing credentials, missing gitignored dependencies, or cross-boundary changes to the orchestrator instead of guessing.

2. **Keep your branch isolated & always check remote git updates before pushing/PRs.**
   - Commit cleanly onto your assigned branch only. **Never** switch branches, merge into `main` or another worker's branch, push to `main`, or commit secrets, caches, or weights.
   - **Before any remote push or PR action, always run `git fetch origin` first:**
     1. Check if `origin/<base>` (e.g. `origin/main`) advanced; if conflicts exist, merge/rebase `origin/<base>` cleanly inside your own worktree and re-run all verification checks before pushing.
     2. Push your branch and verify `git ls-remote origin refs/heads/<branch>` matches `HEAD`.
     3. When a PR is requested, check `gh auth status` and `gh pr list --head <branch> --state all`:
        - **If `gh` is authenticated:** Create the PR (`gh pr create --base <base> --head <branch> --title "<clear title>" --body "<concise summary + verification>"`, using a `/tmp` `--body-file` for clean quoting, or update an existing `OPEN` PR) and verify its URL and `mergeable` state.
        - **If `gh` is missing/unauthenticated:** Record the GitHub compare URL along with a ready-to-paste PR title and concise summary.

3. **No unauthorized delegation or layout changes.**
   - Do not spawn sub-agents (`herdr workspace create`, `herdr tab create`, `herdr pane split`, `herdr agent start`), focus-steal tabs/workspaces, or stop `herdr server` unless explicitly instructed.

4. **Supervise long-running jobs in one blocking bash monitor (zero LLM polling).**
   - For multi-minute/hour builds, trainings, or cloud/GPU runs, **never** poll in repeated short `sleep` tool calls. Detach the runner under `nohup setsid` (with `flock` if sharing a resource) and watch it in **one blocking bash loop** — follow [long-running-monitor.md](./references/long-running-monitor.md).

5. **Report progress and completion against the assignment.**
   - For a tracked assignment, acknowledge the scope and tell the orchestrator when a blocker, cross-worker dependency, or material change affects delivery. Use `herdr agent prompt <orchestrator-target>` and the report path in the handoff. If the target is missing or delivery fails, record it in the report and request a reachable target.
   - Start each notice with `<worker-name> PROGRESS`, `BLOCKED`, or `COMPLETE`. Include the assignment, tested commit or build, checks and results, evidence path, and outstanding work with its owner. For example: “workspace PROGRESS — abc123 built. Mobile dialog capture running. Owner: workspace. Evidence: logs/dialog-check.log.”
   - Use `PROGRESS` while an assigned check is running, queued, or awaiting results. Use `BLOCKED` when progress needs a decision or dependency, naming what would unblock it. Ask the orchestrator to acknowledge reassignment before handing off an unfinished check.
   - Send `COMPLETE` after verifying your assigned checks, artifacts, worktree status, and requested delivery. Record baseline failures or accepted exceptions. Distinguish worker-branch evidence from integrated-build evidence. Write the final report before sending the notice; include any separately assigned integration checks and their owners. A follow-up reopens the affected checks and needs a fresh report for the new revision.
   - **Do not exit your agent session after reporting:** Release any billable remote compute (`colab stop`, cloud VMs) and lockfiles, then remain parked (`idle` in the assigned pane) so follow-up revisions keep your full context warm.
