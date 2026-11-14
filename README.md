# herdr-skills

Production-tested **orchestrator** and **worker** skills for coordinating multi-agent coding workflows inside **Herdr** — covering **both** Herdr CLI architectures:

1. **Herdr Core + Herdr App (`hc` + `herdr-app`)** — `herdr-orchestrator` & `herdr-worker`
2. **Herdr TUI (`herdr` terminal multiplexer)** — `herdr-tui-orchestrator` & `herdr-tui-worker`

Works across the four primary terminal/CLI coding agents inside Herdr: **Claude Code (`claude`)**, **Oh My Pi (`omp` / `pi`)**, **Codex (`codex --no-daemon`)**, and **Antigravity CLI (`agy`)** *(note: desktop GUI IDEs like Antigravity IDE or Cursor do not run inside Herdr `$HC_TERMINAL_ID` / `$HERDR_PANE_ID` terminals)*.

---

## Included Skills

| Skill | Variant | Role | Activation |
| :--- | :--- | :--- | :--- |
| [`herdr-orchestrator`](skills/herdr-orchestrator/SKILL.md) | `hc` + `herdr-app` | Scopes worktrees, writes handoff specs, spawns/steers workers, verifies diffs/PRs | Explicit opt-in (`/herdr-orchestrator`) |
| [`herdr-worker`](skills/herdr-worker/SKILL.md) | `hc` + `herdr-app` | Executes bounded task in an isolated worktree, syncs/opens PR, stays warm (`idle`) | Explicit in worker bootstrap prompt |
| [`herdr-tui-orchestrator`](skills/herdr-tui-orchestrator/SKILL.md) | `herdr` TUI | Same orchestrator discipline adapted to `herdr tab/pane/agent` CLI & `$HERDR_PANE_ID` | Explicit opt-in (`/herdr-tui-orchestrator`) |
| [`herdr-tui-worker`](skills/herdr-tui-worker/SKILL.md) | `herdr` TUI | Same worker discipline adapted to `herdr` TUI panes, reports, and `$HERDR_PANE_ID` | Explicit in worker bootstrap prompt |

---

## Which Variant Do I Need? (`hc` + `herdr-app` vs. `herdr` TUI)

Herdr has two distinct CLI surfaces depending on whether you run the **`herdr-core` daemon + GPUI desktop app** or the **`herdr` TUI terminal multiplexer**:

| Capability | `herdr-orchestrator` / `herdr-worker` (`hc` + `herdr-app`) | `herdr-tui-orchestrator` / `herdr-tui-worker` (`herdr` TUI) |
| :--- | :--- | :--- |
| **Session env var** | `$HC_TERMINAL_ID` (e.g. `t19`) | `$HERDR_PANE_ID` (e.g. `w1:p1`), `$HERDR_WORKSPACE_ID` |
| **Preflight check** | `test -n "${HC_TERMINAL_ID:-}" && hc ls >/dev/null` | `test -n "${HERDR_PANE_ID:-}" && herdr agent list >/dev/null` |
| **Spawn background worker** | `hc run --bg --name <type>-<topic> --cwd "<worktree>" <cmd>` | `herdr tab create --cwd "<worktree>" --label "<type>/<topic>" --no-focus` + `herdr agent start <name> --kind <kind> --pane "<pane_id>"` |
| **Wait / monitor (non-blocking)** | Startup only: `hc wait <name> --timeout 15`; completion: end turn (`idle`) + `<hc>` push or detached `hc run --bg --rm --no-notify` watchdog / scheduled timer | Startup only: `herdr agent wait <name> --state idle`; completion: end turn (`idle`) + `herdr agent prompt` push or detached `nohup setsid` watchdog / timer |
| **Send task / revision** | `hc send <name> "<prompt>"` | `herdr agent prompt <name> "<prompt>"` |
| **Read output** | `hc read --lines 80 <name>` / `hc get <name>` | `herdr agent read <name> --source recent` / `herdr pane read "<pane_id>" --lines 80` |
| **Interrupt mid-turn** | `hc interrupt <name>` | `herdr agent send-keys <name> esc` |
| **Window / layout control** | `herdr-app ls`, `herdr-app status`, `herdr-app do ...` | `herdr workspace ...`, `herdr tab ...`, `herdr pane ...` |
| **Cleanup** | `hc kill <name>; hc rm <name>` | `herdr tab close "<tab_id>"` / `herdr pane close "<pane_id>"` |

---

## Prerequisites: Install Herdr & CLI Tools

Your orchestrator agent **must** be running inside a Herdr-managed terminal (`$HC_TERMINAL_ID` for `hc`/`herdr-app`, or `$HERDR_PANE_ID` for `herdr` TUI) so it can spawn and message workers.

### Option A: Herdr App + `herdr-core` (`hc` + `herdr-app`)

For `herdr-orchestrator` and `herdr-worker`:

```bash
# macOS / Linux (installs Herdr.app + herdr-core / hc)
curl -fsSL https://releases.herdr.dev/app/install.sh | sh

# macOS Homebrew Cask
brew install --cask herdr-app

# Headless / Linux server (herdr-core / hc only, no desktop app)
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
```

Windows (PowerShell):
```powershell
irm https://releases.herdr.dev/app/install.ps1 | iex
# or headless core only:
irm https://releases.herdr.dev/core/install.ps1 | iex
```

Verify inside a Herdr terminal:
```bash
test -n "${HC_TERMINAL_ID:-}" && hc ls
```

### Option B: Herdr TUI (`herdr`)

For `herdr-tui-orchestrator` and `herdr-tui-worker`:

```bash
# macOS / Linux
curl -fsSL https://herdr.dev/install.sh | sh

# Alternative package managers
brew install herdr
mise use -g herdr
```

Windows (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"
```

Verify inside a Herdr TUI pane:
```bash
test -n "${HERDR_PANE_ID:-}" && herdr agent list
```

### Additional CLI Prerequisites

- **`git`** (for per-worker `git worktree` isolation and branch management)
- **At least one terminal coding agent:** `agy` (Antigravity CLI), `claude`, `pi`, `codex`, or `opencode`
- **GitHub CLI (`gh`, optional):** Authenticate with `gh auth login` if you want workers to open/update PRs automatically

---

## Installation

### Option 1: `skills` CLI (`npx skills`)

```bash
# Global (-g) install for hc + herdr-app variant
npx skills add xphiwork-dot/herdr-skills --skill herdr-orchestrator --skill herdr-worker -g

# Or project-level install (omit -g inside your repo)
npx skills add xphiwork-dot/herdr-skills --skill herdr-orchestrator --skill herdr-worker

# Or install the Herdr TUI variant (-g for global, omit for project-level)
npx skills add xphiwork-dot/herdr-skills --skill herdr-tui-orchestrator --skill herdr-tui-worker -g
```

### Option 2: Local Installer Script (`--global` or `--project`)

```bash
git clone https://github.com/xphiwork-dot/herdr-skills.git
cd herdr-skills

# Global install (--global is the default)
./install.sh --variant app --agy         # ~/.gemini/antigravity-cli/skills (Antigravity CLI)
./install.sh --variant app --claude      # ~/.claude/skills (Claude Code)
./install.sh --variant app --omp         # ~/.omp/agent/skills (Oh My Pi / OMP)
./install.sh --variant app --codex       # ~/.codex/skills (Codex)
./install.sh --variant app --pi          # ~/.pi/agent/skills (Pi)
./install.sh --variant app               # ~/.agents/skills (universal shared path)
./install.sh --variant tui --agy         # Herdr TUI variant

# Project-level install (--project [dir], defaults to $PWD)
./install.sh --variant app --project /path/to/repo           # <repo>/.agents/skills (agy / omp)
./install.sh --variant app --project /path/to/repo --claude  # <repo>/.claude/skills
./install.sh --variant app --project /path/to/repo --codex   # <repo>/.codex/skills
./install.sh --variant app --project /path/to/repo --pi      # <repo>/.pi/skills

# Symlink for live skill edits (either --global or --project)
./install.sh --variant all --agy --symlink

# Automatically export built-in CLI dependency skills (hc --skill, herdr-app --skill, herdr --skill)
./install.sh --variant app --agy --with-deps
```

> **Dependency check:** `install.sh` automatically checks for `hc` / `herdr-app` (for `app`) and `herdr` (for `tui`). If a binary is missing, it prints the install command; if installed but its `--skill` file is missing from the destination, it prompts to export it (or does so automatically with `--with-deps`, or skips with `--no-deps`).

> **Antigravity CLI `~/.gemini/config/skills.json` alternative:** `agy` CLI also discovers paths listed in `~/.gemini/config/skills.json` (e.g. `{ "entries": [{ "path": "/path/to/herdr-skills/skills" }] }`).

### Option 3: Pi (`pi` Coding Agent Package)

Add to `~/.pi/agent/settings.json`:

```json
{
  "packages": [
    "git:github.com/xphiwork-dot/herdr-skills"
  ]
}
```

---

## Quickstart & Usage Examples

### 1. Start Your Orchestrator Agent Inside Herdr

Launch your preferred CLI coding agent (`agy`, `claude`, `pi`, `codex`, or `opencode`) **inside a Herdr terminal** (Herdr App/Core or Herdr TUI), then invoke the orchestrator skill explicitly in your prompt:

- **Herdr App / `hc` (`$HC_TERMINAL_ID`):** start your prompt with `/herdr-orchestrator ...` (or ask to *"orchestrate with herdr"*).
- **Herdr TUI (`$HERDR_PANE_ID`):** start your prompt with `/herdr-tui-orchestrator ...`.

---

### 2. Example Prompts

#### Single Worker PR Task (`pi` / `claude` / `codex` worker)

```text
/herdr-orchestrator update README.md to reflect the current main branch and open a PR using a pi deepseek worker
```

What happens automatically:
1. **Preflight & isolation:** Checks `git ls-remote` / `gh auth status` and creates an isolated worktree (`../repo-update-readme` on branch `docs/update-readme`) plus a handoff spec in `~/.local/state/herdr/<project>/tasks/`.
2. **Spawn & wait:** Launches the worker in background (`hc run --bg --name docs-update-readme ...` or `herdr tab create --no-focus` + `herdr agent start`), waits until `idle`, and sends the task with `herdr-worker`.
3. **Sync, verify & PR:** The worker runs `git fetch origin`, resolves any conflicts against `origin/main` inside its worktree, verifies checks, pushes, and opens the PR via `gh pr create`.
4. **Stay warm:** The orchestrator verifies the diff/PR and leaves the worker `idle` for follow-ups.

#### Parallel Multi-Worker Tasks (Separate Worktrees & PRs)

```text
/herdr-orchestrator use two claude workers in parallel: one to fix the login timeout bug, and one to add integration tests
```

Each worker receives its own isolated `git worktree`, branch (`fix/login-timeout`, `test/login-integration`), and independent PR—never sharing a working directory or auto-merging into `main`.

#### Follow-Up Revisions, Screenshots & Cleanup

```text
Send the attached screenshot to docs-update-readme so it fixes the overflowing table, then clean up the worker after I merge the PR.
```

- **Screenshots:** The orchestrator copies user-shared images into `~/.local/state/herdr/<project>/assets/` (never into the git repo) and points the warm worker to that path.
- **Cleanup:** Once you confirm, the orchestrator removes the `hc` terminal / `herdr` tab, deletes the isolated worktree (`git worktree remove` + `prune`), and cleans up the XDG state files.

---

## Key Workflow Guarantees

- **Pragmatic Orchestrator Role:** Delegates substantive code, heavy builds/trainings, parallel tasks, and edits on worker-owned branches—while handling quick 5-second setup/config/housekeeping chores (or anything the user asks to do directly) without bureaucratic overhead.
- **Human-Readable Worker Naming:** Git branches use `<type>/<topic>` (`docs/update-readme-status`), while `hc` / `herdr` agent names use valid hyphenated slugs `<type>-<topic>` (`1–32` chars, no `/`). User-facing updates always use the worker name rather than raw terminal/pane IDs.
- **Per-Worker `git worktree` Isolation:** Every concurrent worker gets its own `git worktree` and branch—with preflight checks for gitignored dependencies (`.venv`, `upstream/`, `data/`) and zero unprompted merges into `main`.
- **Clean XDG State & Screenshot Staging:** Handoff specs (`tasks/`), reports (`reports/`), shared GPU locks (`locks/`), and user-uploaded screenshots (`assets/`) live under `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/`—keeping every git worktree clean.
- **Remote Sync, Conflict Resolution & PR Creation:** Workers always `git fetch origin` before any remote action, resolve conflicts against `origin/<base>` inside their isolated worktree, re-verify gates, and create/update PRs directly via `gh pr create` (with fallback compare URL + ready-to-paste title & summary if `gh` is unauthenticated).
- **Release-to-Idle Non-Blocking Monitoring (Chat Stays Free):** Orchestrators **never** run `hc wait --children ...` or `herdr agent wait` as blocking foreground commands (or turn-holding `bg_*` jobs that trap `omp`/`pi` in `working` status). After dispatching tasks, the orchestrator immediately ends its turn (`idle`) and wakes reactively via worker `hc send` / `herdr agent prompt` pushes, untracked `hc run --bg --rm --no-notify` / `nohup setsid` watchdog jobs, or out-of-turn scheduled timers.
- **Zero-LLM-Polling Long Job Supervision:** Progressive-disclosure `references/` provide detached `nohup setsid` + single blocking bash monitor recipes for long builds and cloud/GPU runs.
- **Warm Workers & Explicit Cleanup:** Completed workers remain parked (`idle`, zero token cost) for instant follow-up revisions until the user confirms full worktree + terminal + state cleanup.

---

## Repository Layout

```text
herdr-skills/
├── skills/
│   ├── herdr-orchestrator/          # hc + herdr-app orchestrator (+ scripts/herdr-watch.sh & references/)
│   ├── herdr-worker/                # hc + herdr-app worker (+ references/)
│   ├── herdr-tui-orchestrator/      # herdr TUI orchestrator (+ scripts/herdr-tui-watch.sh & references/)
│   └── herdr-tui-worker/            # herdr TUI worker (+ references/)
├── .claude-plugin/plugin.json       # Claude Code plugin manifest
├── package.json                     # Pi & skills package manifest
├── install.sh                       # Variant-selectable installer (--variant app|tui|all)
└── LICENSE                          # MIT
```
