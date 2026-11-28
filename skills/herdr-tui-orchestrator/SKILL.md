---
name: herdr-tui-orchestrator
description: >-
  Coordinate coding agents inside the Herdr TUI multiplexer (`herdr` CLI:
  `herdr workspace`, `herdr tab`, `herdr pane`, `herdr agent`). Use only when
  the user explicitly requests `herdr-tui-orchestrator` or asks to orchestrate
  workers inside a Herdr TUI (`HERDR_PANE_ID`) session; never activate merely
  because parallel work is useful.
---

# Herdr TUI Orchestrator (`herdr` CLI)

Opt-in per request for the **Herdr TUI** (`herdr` multiplexer CLI — for `herdr-core` `hc` + `herdr-app`, use `herdr-orchestrator` instead).

Before acting, resolve your pane and workspace with the read-only [herdr-tui-context.sh](./scripts/herdr-tui-context.sh) helper. It uses an exact Codex thread match from Herdr's agent registry when available and otherwise validates the inherited `HERDR_PANE_ID`. If both are missing, the helper looks up the current thread title in the local Codex session index and requires one unregistered Codex pane with that title and foreground directory. Confirm a title-based match against recent conversation text with `herdr pane read <pane_id> --lines 40` before dispatch.

```bash
context=$("<skills-dir>/herdr-tui-orchestrator/scripts/herdr-tui-context.sh") || exit 1
ORCHESTRATOR_PANE=$(jq -er .pane_id <<< "$context")
ORCHESTRATOR_WORKSPACE=$(jq -er .workspace_id <<< "$context")
```

Codex command tools can lose Herdr's environment when the app-server daemon is shared. Launch Codex from its Herdr pane with `codex --no-daemon`, keeping any model and effort flags. If the resolver still can't identify the pane or the inherited value looks stale, have the user run `herdr pane current` from the shell in the intended pane and pass the confirmed `pane_id` as the helper's first argument. A command tool without a pane ID may see whichever pane is focused, even when it belongs to another session. If the identity or server remains unresolved, stop. Never open, attach to, or stop user sessions unprompted. For a named Herdr session, preserve its `HERDR_SOCKET_PATH` in tool calls.

Use the resolved IDs as literal arguments in later tool calls when the shell is fresh. Never run bare `herdr` without subcommands. Inspect capabilities via `herdr --help` and `herdr <workspace|tab|pane|agent> --help`.

## Core Workflow

### 0. Pragmatic Orchestrator Role & User Communication
- **Delegate substantive & worker-owned work; handle quick/meta tasks directly:**
  - **Delegate to workers:** Multi-step feature/experiment code, heavy builds/test suites/trainings, parallel workstreams, and follow-up edits inside an existing worker's isolated worktree/branch (`herdr agent prompt <name> "..."`) so your context stays lean and you never collide with a `working` agent.
  - **Do directly yourself (don't spawn a worker for 5-second chores):** Orchestration/skill/tooling setup, git/worktree/PR housekeeping, quick read-only checks, tiny standalone config/doc tweaks when no worker owns that branch, and **anything the user explicitly asks you to do directly**.
- **Use worker `<name>` with the user:** In all user-facing messages, refer to workers by their descriptive agent name (e.g. `docs-update-readme-status`), **never** raw pane IDs (e.g. `w1:p4`).

### 1. Centralized Worktree Isolation, Branch Discipline & Preflight
- **One centralized worktree + branch per worker:** Create every worker's isolated git worktree under the standardized XDG state directory `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/worktrees/<worker-name>` (never pollute `../` parent workspace folders or share the main checkout):
  ```sh
  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>"
  mkdir -p "$STATE_DIR"/{worktrees,tasks,reports,assets,locks,logs,status}
  git worktree add "$STATE_DIR/worktrees/<type>-<topic>" -b <type>/<topic> <base>
  ```
- **Gitignored dependencies in fresh worktrees:** `git worktree add` omits gitignored directories (`.venv`, `upstream/`, `data/`). Check if tests/scripts need them; symlink **read-only** shared directories (`ln -s`) or document setup in the handoff spec (**never** symlink writable output directories back into the main checkout).
- **No unprompted merges:** Never merge worker branches into `main` or fold separate worktrees into one catch-all branch/PR unless the user explicitly asks. Use stacked branches or ask first when tasks depend on unmerged work.
- **Preflight shared blockers once:** Run quick read-only checks on credentials, remote access (`git ls-remote`), and `gh auth status` before spawning workers.

### 2. Naming & Centralized XDG State Layout
- **Naming rules (`/` in git branches, `-` in agent, workspace & worktree folder names):**
  - **Git branch:** `<type>/<topic>` (e.g. `docs/update-readme-status`)
  - **Herdr agent `<name>` & worktree directory:** `<type>-<topic>` — `1–32` chars of `a-z 0-9 - _ .`, starting with `[a-z0-9]`, **no `/`**.
  - **Worker workspace label:** `└ <type>-<topic>` (set by `herdr-tui-spawn.sh`; the `└ ` prefix marks it as a child of the orchestrator's workspace in the sidebar).
- **Centralized project state & worktree root (`${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/`):**
  - `worktrees/<worker-name>/` — isolated `git worktree` checkouts (1:1 match with agent `<name>`).
  - `tasks/<worker-name>.md` — durable handoff specs (see [handoff-template.md](./references/handoff-template.md)).
  - `reports/<worker-name>.md` — verified worker completion summaries.
  - `assets/<worker-name>-*.png` — user-provided screenshots/reference images. Always copy user images here (never into a git worktree) and pass the path in the handoff spec or prompt.
  - `status/` — worker status inbox written by `herdr-tui-inbox.sh`: `roster.json`, `<worker-name>.json` (current state), `<worker-name>.log` (append-only, tail-friendly).
  - `locks/<resource>.lock` and `logs/` — shared GPU/resource locks and detached logs.

### 3. Spawn Worker Subtree Workspaces & Start Tracked Agents
Unlike `hc run --bg`, `herdr` TUI first provisions a shell pane and then attaches lifecycle tracking via `herdr agent start`:
- **One child workspace per worker, nested under yours (default):** Use the bundled [herdr-tui-spawn.sh](./scripts/herdr-tui-spawn.sh). It runs `herdr workspace create --no-focus` with label `└ <worker-name>`, then reorders it directly below the orchestrator's workspace (`$ORCHESTRATOR_WORKSPACE`, after any existing `└ ` siblings) via the raw-socket `workspace.move` request (the CLI has no `workspace move`). Focus is never stolen. If the move fails (herdr protocol < 16), the worker still runs at the end of the sidebar and a warning is printed.
- **Do not** use `herdr tab create` in your own workspace for workers. Only use `herdr pane split "$ORCHESTRATOR_PANE" --direction right --no-focus` when the user explicitly asks for side-by-side splits.
  ```sh
  # 1. Create the child workspace rooted at the centralized worktree (prints JSON: workspace_id, tab_id, pane_id, label, moved)
  SPAWN_JSON=$("<skills-dir>/herdr-tui-orchestrator/scripts/herdr-tui-spawn.sh" <type>-<topic> "$STATE_DIR/worktrees/<type>-<topic>" "$ORCHESTRATOR_WORKSPACE")
  PANE_ID=$(printf '%s' "$SPAWN_JSON" | jq -r .pane_id)

  # 2. Start the interactive coding agent inside that shell pane (never pass -p print mode)
  #    Codex: --kind codex, then -- --no-daemon followed by requested flags
  #    Claude: --kind claude, then -- --model sonnet --effort medium
  # Codex linked worktrees share Git metadata outside the sandbox working directory.
  GIT_COMMON=$(git -C "$STATE_DIR/worktrees/<type>-<topic>" rev-parse --path-format=absolute --git-common-dir)
  herdr agent start <type>-<topic> --kind codex --pane "$PANE_ID" -- --no-daemon \
    --add-dir "$GIT_COMMON" --add-dir "$STATE_DIR/status" --add-dir "$STATE_DIR/reports" <agent-flags>

  # 3. Wait briefly ONLY for startup readiness (idle; accept workspace trust prompt via send-keys enter if blocked), then submit
  herdr agent wait <type>-<topic> --until idle --timeout 30000
  herdr agent prompt <type>-<topic> "Use the herdr-tui-worker skill (<skills-dir>/herdr-tui-worker/SKILL.md, e.g. ~/.agents/skills or ~/.gemini/.../skills). Execute $STATE_DIR/tasks/<type>-<topic>.md. No subagents."
  ```
  *(Pass the exact installed path to `herdr-tui-worker/SKILL.md`. Pass `--machine "<label-or-id>"` before subcommands when targeting a saved remote SSH machine, and inline `herdr-tui-worker` rules if the remote host lacks the skill file.)*

### 4. Non-Blocking Monitoring ("Release-to-Idle" Across `claude`, `omp`, `codex`, `agy`)
- **NEVER block your turn on completion waits:** Running `herdr agent wait <name>` or `herdr pane wait-output` in a foreground tool call—**or** inside an `omp` background bash job (`bg_*` keeps `omp` stuck in `waiting on 1 job` / `working`!) or an open-FD `&` command in `codex`—locks your pane status in `working` and **blocks the user from chatting** (only use `herdr agent wait --until idle --timeout <ms>` for the brief 1–5s startup readiness step above, never `--wait` on `herdr agent prompt`).
- **End your turn immediately after dispatch (`idle`):** All four CLIs (`claude`, `omp`, `codex`, `agy`) wake automatically via PTY input when `herdr agent prompt` submits text while `idle`:
  1. **Default: status inbox + LLM-free watcher ([herdr-tui-inbox.sh](./scripts/herdr-tui-inbox.sh)).** Workers write their status to files and never prompt you for progress. A detached shell watcher decides when you need to wake. Start both once at dispatch, after the handoff specs exist and before ending your turn:
     ```sh
     INBOX="<skills-dir>/herdr-tui-orchestrator/scripts/herdr-tui-inbox.sh"
     "$INBOX" init "$STATE_DIR" "$ORCHESTRATOR_PANE" <worker-1> <worker-2>   # roster + status/<worker>.{json,log}
     "$INBOX" watch "$STATE_DIR" --detach            # nohup setsid, closed FDs; returns at once in every CLI
     ```
     The watcher checks `status/*.json` and `herdr agent get` every 15s. It sends you **one line** only when a worker is `blocked` or sets `needs`, a worker pane waits on a permission prompt, a worker is idle 20m+ while its status still says working (stalled, interrupted, or never wrote status), a worker agent remains missing for the stall threshold (20m by default, even if its last status was `complete`), or every worker is `complete` **and** idle (`--each` also wakes per completed worker). Wakes queue while you are busy and are delivered once you are idle. Progress never wakes you. The watcher exits after the all-complete wake; restart it after a follow-up.
  2. **Reading updates (cheap):** `"$INBOX" read "$STATE_DIR"` prints one line per worker that changed since your last read, or `no changes`. `"$INBOX" tail "$STATE_DIR" [worker] -n 3` prints the last status lines (`working [at=<epoch>] rev=abc123: <summary>`), like `tail -3 status/<worker>.log | cut -c1-300`. Use `read --all` for a full snapshot. Never poll in a loop yourself.
  3. **CLI-Native Timers (`agy` & `claude` only — never `omp` `bg_*` or `codex`):** In `agy` (`schedule`) or `claude` (`ScheduleWakeup` / `CronCreate` / `run_in_background`), you may add a native out-of-turn timer that lets your turn finish to `idle`. It is optional; the watcher already works in every CLI.
- **Inspect & steer when woken:** Start with `read` / `tail`. Go deeper only when needed: `herdr agent get <name>`, `herdr agent read <name> --source recent`, or `herdr pane read "<pane_id>" --lines 80` (`herdr agent explain <name>` to debug state detection). For long-running builds/GPU jobs and `esc` mid-flight steering, follow [long-running-jobs.md](./references/long-running-jobs.md).
- **Verify every worker claim:** Always verify `<state-dir>/reports/<worker-name>.md`, `git status --short`, `git diff <base> --stat`, test/link/row counts, and remote SHAs before reporting completion.

#### Worker reports and user updates

- At dispatch, record each named worker, its acceptance checks, and who owns verification on the integrated revision. Put the inbox path and `write` command in each handoff. For a follow-up, update the handoff, run `"$INBOX" reopen "$STATE_DIR" <worker> "<reason>"` **before** prompting the worker, and restart the watcher.
- Workers record `working`, `blocked` (with `--needs`), or `complete` with their tested revision, checks, pending items, and a one-line summary. `write complete` refuses while checks are pending or failed, tracked files are uncommitted, or the report is missing or older than the current round. On a handoff between workers, name the receiving owner and keep the check pending until that owner acknowledges it. A worker's `complete` covers its assigned scope only.
- **Readiness gate (mandatory):** Before any user-facing "done", "ready", or "complete" claim, run `"$INBOX" gate "$STATE_DIR"`. It exits 0 only when every assigned worker is `complete`, its agent is idle, its status `rev` is the worktree HEAD with no uncommitted tracked changes, nothing is pending, and its report is current. If it fails, report verification as pending and ask the failing workers what remains. A passing gate covers worker scope only; integrated checks below still apply.
- Track delivery separately: local commit, pushed branch, open PR, and merge are observable milestones. Publishing a PR while checks run is fine when authorized. Say which revision was published, which checks passed, and which checks are pending, failed, or blocked with their owners.
- Call the result ready for review or complete only after verifying all assigned reports, the integrated revision and required checks, and any requested remote delivery. Match evidence to the delivered SHA (or verified identical tree for content checks). Report baseline failures and explicit user-accepted exceptions. When the integrated code changes, rerun affected checks before closing them.

Example user update: “PR #42 was updated to `abc123`. Production build passed. The workspace worker is checking mobile dialogs on that build. Review readiness is pending.”

### 5. Remote Sync, Conflict Resolution, PR Creation & Cleanup
- **Always `git fetch origin` before any remote git or PR action:** Have the worker fetch `origin` first, check for and resolve any conflicts against `origin/<base>` cleanly inside its isolated worktree, re-run verification checks, and push.
- **PR creation (`gh` vs. fallback):** Have the worker check `gh auth status` and `gh pr list --head <branch> --state all`:
  - If authenticated: create (`gh pr create --base <base> --head <branch> --title "<clear title>" --body "<concise summary + verification>"`) or update an existing `OPEN` PR and report its URL + mergeability.
  - If `gh` is unavailable or unauthenticated: push the branch and report the compare URL plus a ready-to-paste PR title and concise summary.
- **Release compute & keep workers warm:** Immediately stop billable remote compute (`colab stop`, cloud VMs), cancel active timers, and stop any leftover inbox watcher (`"$INBOX" stop "$STATE_DIR"`), but **leave completed worker workspaces open (`idle`)** so revisions can be sent instantly via `herdr agent prompt <name> "<feedback>"`.
- **Proactive cleanup prompt:** Closing a worker workspace (`herdr workspace close "<workspace_id>"`) does **not** delete git worktrees, branches, caches, or state files. When work finishes, list the completed workers, their `└ <name>` workspaces, worktrees (`$STATE_DIR/worktrees/<name>`), branches, and state/asset files and ask user confirmation before running `git worktree remove "$STATE_DIR/worktrees/<name>"` + `git worktree prune`, `herdr workspace close "<workspace_id>"` (or `herdr pane close "<pane_id>"` for user-requested splits), and state cleanup (never stopping `herdr server` or closing user-owned workspaces/panes — only close `└ ` workspaces you spawned).
