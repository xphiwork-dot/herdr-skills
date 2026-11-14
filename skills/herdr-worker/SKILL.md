---
name: herdr-worker
description: >-
  Execute a bounded assignment as a Herdr orchestration worker under herdr-core (hc).
  Use only when the assigning agent or user explicitly specifies the herdr-worker
  skill; do not activate automatically.
---

# Herdr Worker

Activate only when the assigning agent or user explicitly specifies `herdr-worker` (including `<hc from="..." reach="...">` assignments). Follow higher-priority host rules and the assignment; this skill grants no extra permissions.

## Worker Rules

1. **Stay strictly within your assigned boundaries.**
   - Read the full handoff spec (under `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/tasks/` or the path in your prompt), relevant repo docs/code, and any referenced screenshots under `.../assets/` before editing.
   - Keep scratch files, logs, lockfiles, and reference screenshots inside `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/` (or `/tmp`)—**never** copy reference screenshots or temp artifacts into the git worktree unless explicitly instructed.
   - Edit only your owned files in your assigned worktree. Flag missing credentials, missing gitignored dependencies, or cross-boundary changes to the orchestrator instead of guessing.

2. **Keep your branch isolated & always check remote git updates before pushing/PRs.**
   - Commit cleanly onto your assigned branch only. **Never** switch branches, merge into `main` or another worker's branch, push to `main`, or commit secrets, caches, or weights.
   - **Before any remote push or PR action, always run `git fetch origin` first:**
     1. Check if `origin/<base>` (e.g. `origin/main`) advanced; if conflicts exist, merge/rebase `origin/<base>` cleanly inside your own worktree and re-run all verification checks before pushing.
     2. Push your branch and verify `git ls-remote origin refs/heads/<branch>` matches `HEAD`.
     3. When a PR is requested, check `gh auth status` and `gh pr list --head <branch> --state all`:
        - **If `gh` is authenticated:** Create the PR (`gh pr create --base <base> --head <branch> --title "<clear title>" --body "<concise summary + verification>"`, using a `/tmp` `--body-file` for clean quoting, or update an existing `OPEN` PR) and verify its URL and `mergeable` state.
        - **If `gh` is missing/unauthenticated:** Report the GitHub compare URL along with a ready-to-paste PR title and concise summary.

3. **No unauthorized delegation or UI changes.**
   - Do not spawn sub-agents (`hc run` agents), modify the Herdr window (`herdr-app do ...`), or stop/restart `hc server` unless explicitly instructed.

4. **Supervise long-running jobs in one blocking bash monitor (zero LLM polling).**
   - For multi-minute/hour builds, trainings, or cloud/GPU runs, **never** poll in repeated short `sleep` tool calls. Detach the runner under `nohup setsid` (with `flock` if sharing a resource) and watch it in **one blocking bash loop** that pushes real state transitions via `hc send <parent-id> "<worker-name> milestone: <event>"` — follow [long-running-monitor.md](./references/long-running-monitor.md).

5. **Report verified results via `hc send`, then stay idle.**
   - Verify all required outputs, tests/links, clean `git status`, and commit/PR state on disk before claiming `COMPLETE` (distinguish verified facts from assumptions).
   - Send one concise final (or blocked) report via `hc send <parent-id> "<summary>"` (write long reports to the designated file and send its path + key metrics + commit/PR URL).
   - **Do not exit your session after reporting:** Release any billable remote compute (`colab stop`, cloud VMs) and lockfiles, then remain parked (`idle`) so follow-up revisions from the orchestrator keep your full context warm.
