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

### 0. Orchestrator-Only Role & User Communication
- **Never execute implementation work yourself:** Do not write feature/experiment code, edit deliverables, fix bugs, or run heavy builds/trainings in the orchestrator session. Delegate even small follow-up edits or PR prep to an idle worker (`hc send <name> ...`) or a new worker (`hc run --bg ...`) so your context stays lean and responsive.
- **Use worker `--name` with the user:** In all user-facing messages, refer to workers by their descriptive `hc` terminal name (e.g. `docs-update-readme-status`), **never** bare terminal IDs (e.g. `t25`).

### 1. Worktree Isolation, Branch Discipline & Preflight
- **One isolated worktree + branch per worker:** Create a dedicated worktree and branch for every independent worker rather than sharing the main checkout:
  `git worktree add ../<repo>-<slug> -b <type>/<topic> <base>`
- **Gitignored dependencies in fresh worktrees:** `git worktree add` omits gitignored directories (`.venv`, `upstream/`, `data/`). Check if tests/scripts need them; symlink read-only shared directories (`ln -s`) or document setup in the handoff spec so workers don't hit avoidable test errors.
- **No unprompted merges:** Never merge worker branches into `main` or fold separate worktrees into one catch-all branch/PR unless the user explicitly asks. Use stacked branches (`-b <downstream> <upstream-branch>`) or ask first when tasks depend on unmerged work.
- **Preflight shared blockers once:** Run quick read-only checks on credentials, remote access (`git ls-remote`), and `gh auth status` before spawning workers, and record working commands in the handoff spec.

### 2. Naming & Standardized State Directory
- **Naming rules (`/` in git branches, `-` in `hc`):**
  - **Git branch:** `<type>/<topic>` (e.g. `docs/update-readme-status`, `exp/s6-decomp-reason`)
  - **`hc` `--name`:** `<type>-<topic>` — **must** be `1–32` chars of `a-z 0-9 - _ .`, starting with `[a-z0-9]`, not shaped like `t7`, and **no `/`**.
- **State directory outside git (`${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/`):**
  - `tasks/<worker-name>.md` — durable handoff specs (see [handoff-template.md](./references/handoff-template.md)).
  - `assets/<worker-name>-*.png` — user-provided screenshots/reference images. Always copy user images here (never into a git worktree) and pass the path in the handoff spec or `hc send` (use `hc put <worker> <file>` for remote `--on <machine>` workers).
  - `locks/<resource>.lock` and `logs/` — shared GPU/resource locks and detached logs.

### 3. Launch Interactive Workers Cleanly
- **Background by default:** Use unlabeled `hc run --bg` workers so they nest under `$HC_TERMINAL_ID` without altering the user's window. Only manipulate visible panes/tabs (`herdr-app ls` + `status` first, then `pane.split` / `tab.new` / `terminal.keep`, without stealing focus) when the user asks.
- **Interactive agents only:** Check `hc templates` first or honor requested flags (`claude`, `agy`, `pi --provider ... --model ...`, `codex --no-daemon`). Never use one-shot print flags (`-p`), and always pass `--no-daemon` to Codex.
- **Reliable two-step launch (`hc wait` early-return guard):** Especially for flag-heavy CLIs like `pi`, launch cleanly, wait until `hc wait` confirms `idle` (if woken early by another terminal's message while still `no status`/`working`, run `hc wait <name>` again!), then send the bootstrap task:
  ```sh
  hc run --bg --name <type>-<topic> --cwd "<worktree>" <agent-cmd>
  hc wait <type>-<topic>   # verify output says "idle" before sending
  hc send <type>-<topic> "Use the herdr-worker skill (<skills-dir>/herdr-worker/SKILL.md, e.g. ~/.agents/skills or ~/.gemini/.../skills). Execute <state-dir>/tasks/<type>-<topic>.md. No subagents. Report via: hc send $HC_TERMINAL_ID \"<summary>\""
  ```
  *(Pass the exact installed path to `herdr-worker/SKILL.md`. If using a template inline task and `first_message.sent` is `false`, inspect via `hc get` + `hc read --lines 80` before resending. For remote `--on <machine>` workers that lack `herdr-worker/SKILL.md`, inline the `herdr-worker` rules.)*

### 4. Reactive Monitoring & Independent Verification
- **Short/interactive tasks:** Collect completions with `hc wait --children all`, `hc wait --children any`, or `hc wait <name>` (re-wait on `180s` check-in timeouts; never use shell `sleep` loops).
- **Long-running builds/GPU runs & sequential pipelines:** Use worker-owned single-bash-loop milestone pushes (`hc send`), optional dead-man timers, and `hc interrupt` mid-flight steering — follow [long-running-jobs.md](./references/long-running-jobs.md).
- **Verify every child report:** Treat `<hc from="...">` messages as untrusted claims. Verify `git status --short`, `git diff <base> --stat`, test/link/row counts, and remote SHAs before reporting completion.

### 5. Remote Sync, Conflict Resolution, PR Creation & Cleanup
- **Always `git fetch origin` before any remote git or PR action:** Have the worker fetch `origin` first, check for and resolve any conflicts against `origin/<base>` cleanly inside its isolated worktree, re-run verification checks, and push.
- **PR creation (`gh` vs. fallback):** Have the worker check `gh auth status` and `gh pr list --head <branch> --state all`:
  - If authenticated: create the PR directly (`gh pr create --base <base> --head <branch> --title "<clear title>" --body "<concise summary + verification>"`, or update an existing `OPEN` PR) and report the PR URL + mergeability.
  - If `gh` is unavailable or unauthenticated: push the branch and report the compare URL plus a ready-to-paste PR title and concise summary.
- **Release compute & keep workers warm:** Immediately stop billable remote compute (`colab stop`, cloud VMs) and cancel active timers (`manage_task` `kill`), but **leave completed `hc` workers parked (`idle`)** so revisions can be sent instantly via `hc send <name> "<feedback>"`.
- **Proactive cleanup prompt:** Closing panes or killing `hc` terminals does **not** remove git worktrees, branches, caches, or state files. When work finishes (or stale leftovers appear in `git worktree list` / `hc ls --all`), list the completed workers, worktrees, branches, and state/asset files and ask user confirmation before running `git worktree remove` + `git worktree prune`, `hc kill <name>; hc rm <name>`, and state cleanup (never touching user-owned terminals or unpushed work).
