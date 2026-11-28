---
name: herdr-tui-worker
description: >-
  Execute a bounded assignment as a Herdr TUI orchestration worker (`herdr` CLI /
  `HERDR_PANE_ID`). Use only when the assigning agent or user explicitly
  specifies the herdr-tui-worker skill; do not activate automatically.
---

# Herdr TUI Worker (`herdr` CLI)

Activate only when the assigning agent or user explicitly specifies `herdr-tui-worker`. Follow higher-priority host rules and the assignment; this skill grants no extra permissions.

When a pane address is needed and the Codex environment omitted it, look up the worker name from your handoff with `herdr agent get <worker-name>`. Verify the assigned worktree and recent handoff text with `herdr pane read <pane_id> --lines 40` before using the address.

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

5. **Record status in the inbox; do not prompt the orchestrator for progress.**
   - Your status lives in `<state-dir>/status/<worker-name>.json` plus an append-only `<worker-name>.log`. Write it only with the inbox script named in your handoff (normally `<skills-dir>/herdr-tui-orchestrator/scripts/herdr-tui-inbox.sh`), run from inside your worktree so it records your HEAD:
     ```sh
     "$INBOX" write "$STATE_DIR" <worker-name> working  --summary "jest running on abc123" --check build=pass --check jest=pending
     "$INBOX" write "$STATE_DIR" <worker-name> blocked  --summary "SSO user sees zero workspaces" --needs "a workspace visible to the SSO user"
     "$INBOX" write "$STATE_DIR" <worker-name> complete --summary "build+jest pass; report written" --check jest=pass
     ```
   - Writing is free: nobody is woken by `working` updates. Write `working` when you start (and again on each follow-up), then after real milestones (build passed, check started or finished). Keep `--summary` to one line. Put details in your report, not the status.
   - Write `blocked --needs "<what would unblock you>"` when you need a decision or dependency; a watcher wakes the orchestrator for it. Record cross-worker dependencies the same way, naming the other worker. Use `--pending "<item> (owner: <name>)"` for work still outstanding, and ask the orchestrator to acknowledge reassignment before handing off an unfinished check.
   - Write `complete` **last**: after your assigned checks, artifacts, commits, requested delivery, and final report (`<state-dir>/reports/<worker-name>.md`) are done. The script refuses `complete` while a check is `pending` or `fail`, tracked files are uncommitted, or the report is missing or older than the current round; fix the cause or stay `working`. Mark known baseline failures as `--check <name>=baseline` and explain them in the report. Distinguish worker-branch evidence from integrated-build evidence there. Do not keep working after `complete`; if you must, write `working` first.
   - If the first inbox write fails, read the orchestrator target from status/roster.json and send a single BLOCKED notification with the write error via `herdr agent prompt`. If that also fails, surface both errors in your pane. A fallback report in /tmp alone cannot notify the parent.
   - Otherwise only prompt the orchestrator directly (`herdr agent prompt <orchestrator-target> "<worker-name> BLOCKED|COMPLETE — <one line>"`) when the handoff says no inbox exists. If the script is unavailable on your host, write the same JSON fields (`worker, state, rev, worktree, checks, pending, needs, summary, seq, at, working_since`) atomically (temp file + `mv`) and append a `<state> [at=<epoch>]: <summary>` line to the log.
   - **Do not exit your agent session after reporting:** Release any billable remote compute (`colab stop`, cloud VMs) and lockfiles, then remain parked (`idle` in the assigned pane) so follow-up revisions keep your full context warm.
