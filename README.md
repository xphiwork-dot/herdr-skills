# herdr-skills

Production-tested **orchestrator** and **worker** skills for coordinating multi-agent coding workflows inside **Herdr** — covering **both** Herdr CLI architectures:

1. **Herdr Core + Herdr App (`hc` + `herdr-app`)** — `herdr-orchestrator` & `herdr-worker`
2. **Herdr TUI (`herdr` terminal multiplexer)** — `herdr-tui-orchestrator` & `herdr-tui-worker`

Works across terminal/CLI coding agents that run inside Herdr panes/terminals: **Antigravity CLI (`agy`)**, **Claude Code (`claude`)**, **Pi (`pi`)**, **Codex (`codex`)**, and **OpenCode** *(note: desktop GUI IDEs like Antigravity IDE or Cursor do not run inside Herdr `$HC_TERMINAL_ID` / `$HERDR_PANE_ID` terminals)*.

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
| **Wait for readiness / done** | `hc wait <name>` / `hc wait --children all` | `herdr agent wait <name> --state idle` |
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
./install.sh --variant app               # ~/.agents/skills (universal / OpenCode)
./install.sh --variant app --claude      # ~/.claude/skills (Claude Code)
./install.sh --variant app --codex       # ~/.codex/skills (Codex)
./install.sh --variant app --pi          # ~/.pi/agent/skills (Pi)
./install.sh --variant tui --agy         # Herdr TUI variant

# Project-level install (--project [dir], defaults to $PWD)
./install.sh --variant app --project /path/to/repo           # <repo>/.agents/skills (agy CLI / OpenCode)
./install.sh --variant app --project /path/to/repo --claude  # <repo>/.claude/skills
./install.sh --variant app --project /path/to/repo --codex   # <repo>/.codex/skills
./install.sh --variant app --project /path/to/repo --pi      # <repo>/.pi/skills

# Symlink for live skill edits (either --global or --project)
./install.sh --variant all --agy --symlink
```

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

## Key Workflow Guarantees

- **Strict Orchestrator-Only Role:** The orchestrator never writes feature code or edits deliverables directly; even small follow-up tweaks are delegated to warm workers so orchestrator context stays lean and responsive.
- **Human-Readable Worker Naming:** Git branches use `<type>/<topic>` (`docs/update-readme-status`), while `hc` / `herdr` agent names use valid hyphenated slugs `<type>-<topic>` (`1–32` chars, no `/`). User-facing updates always use the worker name rather than raw terminal/pane IDs.
- **Per-Worker `git worktree` Isolation:** Every concurrent worker gets its own `git worktree` and branch—with preflight checks for gitignored dependencies (`.venv`, `upstream/`, `data/`) and zero unprompted merges into `main`.
- **Clean XDG State & Screenshot Staging:** Handoff specs (`tasks/`), reports (`reports/`), shared GPU locks (`locks/`), and user-uploaded screenshots (`assets/`) live under `${XDG_STATE_HOME:-$HOME/.local/state}/herdr/<project-slug>/`—keeping every git worktree clean.
- **Remote Sync, Conflict Resolution & PR Creation:** Workers always `git fetch origin` before any remote action, resolve conflicts against `origin/<base>` inside their isolated worktree, re-verify gates, and create/update PRs directly via `gh pr create` (with fallback compare URL + ready-to-paste title & summary if `gh` is unauthenticated).
- **Zero-LLM-Polling Long Job Supervision:** Progressive-disclosure `references/` provide detached `nohup setsid` + single blocking bash monitor recipes for long builds and cloud/GPU runs.
- **Warm Workers & Explicit Cleanup:** Completed workers remain parked (`idle`, zero token cost) for instant follow-up revisions until the user confirms full worktree + terminal + state cleanup.

---

## Repository Layout

```text
herdr-skills/
├── skills/
│   ├── herdr-orchestrator/          # hc + herdr-app orchestrator (+ references/)
│   ├── herdr-worker/                # hc + herdr-app worker (+ references/)
│   ├── herdr-tui-orchestrator/      # herdr TUI orchestrator (+ references/)
│   └── herdr-tui-worker/            # herdr TUI worker (+ references/)
├── .claude-plugin/plugin.json       # Claude Code plugin manifest
├── package.json                     # Pi & skills package manifest
├── install.sh                       # Variant-selectable installer (--variant app|tui|all)
└── LICENSE                          # MIT
```
