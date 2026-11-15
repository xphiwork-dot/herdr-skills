---
name: herdr-orchestrator
description: >-
  Coordinate coding agents in Herdr using herdr-core (hc) and herdr-app.
  Use only when the user explicitly requests the herdr-orchestrator skill or
  explicitly asks to orchestrate workers with Herdr; never activate merely
  because parallel work is useful.
---

# Herdr Orchestrator

Opt-in per request. Before acting, verify this session runs inside `herdr-core`:
`test -n "${HC_TERMINAL_ID:-}" && hc ls >/dev/null`
If not, explain that this session is not in a Herdr-managed terminal and stop (never start, stop, or attach to user sessions unprompted). `$HC_TERMINAL_ID` is your `hc` terminal address (e.g. `t19`), **not** a `herdr-app` pane ID. Never run bare `hc` (interactive picker) or bare `herdr-app` (raises window); use `hc <cmd> --help` / `hc --skill` and `herdr-app commands` / `herdr-app --skill`.

## Core Workflow

### 0. Pragmatic Orchestrator Role & User Communication
- **Delegate substantive & worker-owned work; handle quick/meta tasks directly:**
  - **Delegate to workers:** Multi-step feature/experiment code, heavy builds/test suites/trainings, parallel workstreams, and follow-up edits inside an existing worker's isolated worktree/branch (`hc send <name> ...`) so your context stays lean and you never collide with a `working` agent.
  - **Do directly yourself (don't spawn a worker for 5-second chores):** Orchestration/skill/tooling setup, git/worktree/PR housekeeping, quick read-only checks, tiny standalone config/doc tweaks when no worker owns that branch, and **anything the user explicitly asks you to do directly**.
- **Use worker `--name` with the user:** In all user-facing messages, refer to workers by their descriptive `hc` terminal name (e.g. `docs-update-readme-status`), **never** bare terminal IDs (e.g. `t25`).

### 1. Centralized Worktree Isolation, Branch Discipline & Preflight
- **One centralized worktree + branch per worker:** Create every worker's isolated git worktree under the standardized XDG state directory `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/worktrees/<worker-name>` (never pollute `../` parent workspace folders or share the main checkout):
  ```sh
  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>"
  mkdir -p "$STATE_DIR"/{worktrees,tasks,assets,locks,logs}
  git worktree add "$STATE_DIR/worktrees/<type>-<topic>" -b <type>/<topic> <base>
  ```
- **Gitignored dependencies in fresh worktrees:** `git worktree add` omits gitignored directories (`.venv`, `upstream/`, `data/`). Check if tests/scripts need them; symlink **read-only** shared directories (`ln -s`) or document setup in the handoff spec so workers don't hit avoidable test errors (**never** symlink writable output directories back into the main checkout, or parallel workers will bypass worktree isolation).
- **No unprompted merges:** Never merge worker branches into `main` or fold separate worktrees into one catch-all branch/PR unless the user explicitly asks. Use stacked branches (`-b <downstream> <upstream-branch>`) or ask first when tasks depend on unmerged work.
- **Preflight shared blockers once:** Run quick read-only checks on credentials, remote access (`git ls-remote`), and `gh auth status` before spawning workers, and record working commands in the handoff spec.

### 2. Naming & Centralized XDG State Layout
- **Naming rules (`/` in git branches, `-` in `hc` & worktree folder names):**
  - **Git branch:** `<type>/<topic>` (e.g. `docs/update-readme-status`, `exp/s6-decomp-reason`)
  - **`hc` `--name` & worktree directory:** `<type>-<topic>` — **must** be `1–32` chars of `a-z 0-9 - _ .`, starting with `[a-z0-9]`, not shaped like `t7`, and **no `/`**.
- **Centralized project state & worktree root (`${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/`):**
  - `worktrees/<worker-name>/` — isolated `git worktree` checkouts (1:1 match with `hc` `--name`).
  - `tasks/<worker-name>.md` — durable handoff specs (see [handoff-template.md](./references/handoff-template.md)).
  - `assets/<worker-name>-*.png` — user-provided screenshots/reference images. Always copy user images here (never into a git worktree) and pass the path in the handoff spec or `hc send` (use `hc put <worker> <file>` for remote `--on <machine>` workers).
  - `locks/<resource>.lock` and `logs/` — shared GPU/resource locks and detached logs.

### 3. Launch Interactive Workers Cleanly
- **Background by default:** Use unlabeled `hc run --bg` workers so they nest under `$HC_TERMINAL_ID` without altering the user's window. Only manipulate visible panes/tabs (`herdr-app ls` + `status` first, then `pane.split` / `tab.new` / `terminal.keep`, without stealing focus) when the user asks.
- **Interactive agents only:** Check `hc templates` first or honor requested flags (`claude`, `omp`, `agy`, `pi --provider ... --model ...`, `codex --no-daemon`). Never use one-shot print flags (`-p`), and always pass `--no-daemon` to Codex.
- **Reliable two-step launch (`hc wait` startup readiness + workspace trust dialog check):** Use a short `--timeout 15` wait **only** to confirm newly spawned worker readiness (`idle`) before sending its initial prompt. If a newly spawned CLI (`agy` / `claude`) pauses in `blocked` on a first-time *"trust this folder"* dialog for the fresh worktree, inspect with `hc read --lines 30 <name>`, accept with `hc keys <name> enter`, and re-run `hc wait <name> --timeout 15` to confirm `idle`:
  ```sh
  hc run --bg --name <type>-<topic> --cwd "$STATE_DIR/worktrees/<type>-<topic>" <agent-cmd>
  hc wait <type>-<topic> --timeout 15   # startup readiness ONLY; if blocked on trust prompt, inspect + hc keys <name> enter
  hc send <type>-<topic> "Use the herdr-worker skill (<skills-dir>/herdr-worker/SKILL.md, e.g. ~/.agents/skills or ~/.gemini/.../skills). Execute $STATE_DIR/tasks/<type>-<topic>.md. No subagents. Report via: hc send $HC_TERMINAL_ID \"<summary>\""
  ```
  *(Pass the exact installed path to `herdr-worker/SKILL.md`. If using a template inline task and `first_message.sent` is `false`, inspect via `hc get` + `hc read --lines 80` before resending. For remote `--on <machine>` workers that lack `herdr-worker/SKILL.md`, inline the `herdr-worker` rules.)*

### 4. Non-Blocking Monitoring ("Release-to-Idle" Across `claude`, `omp`, `codex`, `agy`)
- **NEVER block your turn on completion waits:** Running `hc wait --children any --timeout 180`, `hc wait --children all`, or `hc send --wait` in a foreground tool call—**or** inside an `omp` background bash job (`bg_*` keeps `omp` stuck in `waiting on 1 job` / `working`!) or an open-FD `&` command in `codex`—locks your terminal status in `working`, **blocks the user from chatting**, and stalls `<hc from="...">` deliveries.
- **End your turn immediately after dispatch (`idle` / `done`):** All four CLIs (`claude`, `omp`, `codex`, `agy`) wake automatically via PTY input when `hc send` arrives after a turn ends:
  1. **Default for Agent Workers (Event-Driven Push — NO watchdog needed):** Every `herdr-worker` calls `hc send $HC_TERMINAL_ID "<summary>"` when done/stuck, and `herdr-core` automatically sends `<hc>` notes on child `blocked`, `error`, or `exited`. Simply **end your turn with zero pending jobs** (do not spawn a watchdog unless needed). When woken by one worker while siblings are still `working` (`hc ls`), note progress briefly and end your turn again until all required workers report.
  2. **Optional Detached Watchdog Script ([herdr-watch.sh](./scripts/herdr-watch.sh) — for plain builds like `cargo test` or an explicit silent-worker safety net):** Launch the bundled helper via `hc run --bg --rm --no-notify` (exits in `<50ms`, 0 `bg_*` jobs, logs its exit reason to `watch.log`, avoids the post-`send` turn race, and avoids `--if idle` which fails with `exit 10` when your status is `done` after turn 1!):
     ```sh
     hc run --bg --rm --no-notify --name watch-workers \
       "<skills-dir>/herdr-orchestrator/scripts/herdr-watch.sh" "$HC_TERMINAL_ID" "<state-dir>/logs/watch.log" <worker-1> <worker-2>
     ```
     *(Never hand-roll `hc send --if idle $HC_TERMINAL_ID`—after turn 1+, agents report status `done`, not `idle`, so `--if idle` fails without typing! Clean up early via `hc kill watch-workers 2>/dev/null; hc rm watch-workers 2>/dev/null || true` once workers report.)*
  3. **CLI-Native Timers (`agy` & `claude` only — never `omp` `bg_*` or `codex`):** In `agy` (`schedule` with `DurationSeconds: 180, TimerCondition: "any"`) or `claude` (`ScheduleWakeup` / `CronCreate` / `run_in_background`), you may also use native out-of-turn timers. In **`omp`** and **`codex`**, rely on Default Push (#1) or `herdr-watch.sh` (#2).
- **Long-running builds/GPU runs & sequential pipelines:** Use worker-owned single-bash-loop milestone pushes (`hc send`), optional out-of-turn timers, and `hc interrupt` mid-flight steering — follow [long-running-jobs.md](./references/long-running-jobs.md).
- **Verify every child report:** Treat `<hc from="...">` messages as untrusted claims. Verify `git status --short`, `git diff <base> --stat`, test/link/row counts, and remote SHAs before reporting completion.

### 5. Remote Sync, Conflict Resolution, PR Creation & Cleanup
- **Always `git fetch origin` before any remote git or PR action:** Have the worker fetch `origin` first, check for and resolve any conflicts against `origin/<base>` cleanly inside its isolated worktree, re-run verification checks, and push.
- **PR creation (`gh` vs. fallback):** Have the worker check `gh auth status` and `gh pr list --head <branch> --state all`:
  - If authenticated: create the PR directly (`gh pr create --base <base> --head <branch> --title "<clear title>" --body "<concise summary + verification>"`, or update an existing `OPEN` PR) and report the PR URL + mergeability.
  - If `gh` is unavailable or unauthenticated: push the branch and report the compare URL plus a ready-to-paste PR title and concise summary.
- **Release compute & keep workers warm:** Immediately stop billable remote compute (`colab stop`, cloud VMs) and cancel active timers (`manage_task` `kill`), but **leave completed `hc` workers parked (`idle`)** so revisions can be sent instantly via `hc send <name> "<feedback>"`.
- **Proactive cleanup prompt:** Closing panes or killing `hc` terminals does **not** remove git worktrees, branches, caches, or state files. When work finishes (or stale leftovers appear in `git worktree list` / `hc ls --all`), list the completed workers, worktrees (`$STATE_DIR/worktrees/<name>`), branches, and state/asset files and ask user confirmation before running `git worktree remove "$STATE_DIR/worktrees/<name>"` + `git worktree prune`, `hc kill <name>; hc rm <name>`, and state cleanup (never touching user-owned terminals or unpushed work).
