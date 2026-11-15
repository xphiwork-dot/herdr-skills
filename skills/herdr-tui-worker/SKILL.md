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
   - Do not spawn sub-agents (`herdr tab create`, `herdr pane split`, `herdr agent start`), focus-steal tabs/workspaces, or stop `herdr server` unless explicitly instructed.

4. **Supervise long-running jobs in one blocking bash monitor (zero LLM polling).**
   - For multi-minute/hour builds, trainings, or cloud/GPU runs, **never** poll in repeated short `sleep` tool calls. Detach the runner under `nohup setsid` (with `flock` if sharing a resource) and watch it in **one blocking bash loop** — follow [long-running-monitor.md](./references/long-running-monitor.md).

5. **Write a verified report, notify if requested, and stay idle.**
   - Verify all required outputs, tests/links, clean `git status`, and commit/PR state on disk before claiming `COMPLETE`.
   - Write your concise verified summary (key metrics, commit SHA, PR URL or compare link + title/summary) to `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/reports/<worker-name>.md`, and if your prompt specifies an orchestrator agent target, send a concise completion notice via `herdr agent prompt <orchestrator-target> "<worker-name> COMPLETE: <summary>"`.
   - **Do not exit your agent session after reporting:** Release any billable remote compute (`colab stop`, cloud VMs) and lockfiles, then remain parked (`idle` in `$HERDR_PANE_ID`) so follow-up revisions keep your full context warm.
