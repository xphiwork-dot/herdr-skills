#!/usr/bin/env bash
set -euo pipefail

VARIANT="all"
SCOPE="global"
PROJECT_DIR="$PWD"
AGENT="default"
CUSTOM_DEST=""
MODE="copy"
WITH_DEPS="prompt"

usage() {
  cat <<'EOF'
Install Herdr orchestration & worker skills for terminal coding agents.

Usage:
  ./install.sh [options]

Options:
  --variant <app|tui|all>   Which Herdr CLI variant to install (default: all)
                              app -> herdr-orchestrator, herdr-worker (hc + herdr-app)
                              tui -> herdr-tui-orchestrator, herdr-tui-worker (herdr TUI)
                              all -> all four skills
  --global                  Install at user/global level under $HOME (default)
  --project [dir]           Install at project level under [dir] (default: $PWD)
                            Uses .agents/skills (or .claude/skills, .codex/skills, .pi/skills)
  --agy, --antigravity      Target Antigravity CLI (~/.gemini/antigravity-cli/skills globally,
                            or <project>/.agents/skills at project level)
  --claude                  Target Claude Code (~/.claude/skills or <project>/.claude/skills)
  --codex                   Target Codex (~/.codex/skills or <project>/.codex/skills)
  --pi                      Target Pi (~/.pi/agent/skills or <project>/.pi/skills)
  --dest <dir>              Explicit destination skills directory (overrides scope/agent)
  --with-deps               Automatically export hc / herdr-app / herdr --skill into dest
  --no-deps                 Skip dependency check / --skill export prompt
  --symlink                 Symlink skill folders instead of copying
  -h, --help                Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      VARIANT="${2:-}"
      shift 2
      ;;
    --global)
      SCOPE="global"
      shift
      ;;
    --project|--local)
      SCOPE="project"
      if [[ $# -gt 1 && "${2:-}" != -* ]]; then
        PROJECT_DIR="$2"
        shift 2
      else
        PROJECT_DIR="$PWD"
        shift
      fi
      ;;
    --dest)
      CUSTOM_DEST="${2:-}"
      shift 2
      ;;
    --agy|--antigravity)
      AGENT="agy"
      shift
      ;;
    --claude)
      AGENT="claude"
      shift
      ;;
    --codex)
      AGENT="codex"
      shift
      ;;
    --pi)
      AGENT="pi"
      shift
      ;;
    --with-deps)
      WITH_DEPS="yes"
      shift
      ;;
    --no-deps)
      WITH_DEPS="no"
      shift
      ;;
    --symlink)
      MODE="symlink"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$VARIANT" in
  app) SKILLS=("herdr-orchestrator" "herdr-worker") ;;
  tui) SKILLS=("herdr-tui-orchestrator" "herdr-tui-worker") ;;
  all) SKILLS=("herdr-orchestrator" "herdr-worker" "herdr-tui-orchestrator" "herdr-tui-worker") ;;
  *)
    echo "Invalid --variant '$VARIANT' (expected: app, tui, or all)" >&2
    exit 1
    ;;
esac

if [[ -n "$CUSTOM_DEST" ]]; then
  DEST="$CUSTOM_DEST"
elif [[ "$SCOPE" == "global" ]]; then
  case "$AGENT" in
    agy) DEST="${HOME}/.gemini/antigravity-cli/skills" ;;
    claude) DEST="${HOME}/.claude/skills" ;;
    codex) DEST="${HOME}/.codex/skills" ;;
    pi) DEST="${HOME}/.pi/agent/skills" ;;
    default) DEST="${HOME}/.agents/skills" ;;
  esac
else
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  case "$AGENT" in
    claude) DEST="${PROJECT_DIR}/.claude/skills" ;;
    codex) DEST="${PROJECT_DIR}/.codex/skills" ;;
    pi) DEST="${PROJECT_DIR}/.pi/skills" ;;
    agy|default) DEST="${PROJECT_DIR}/.agents/skills" ;;
  esac
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$DEST"

for skill in "${SKILLS[@]}"; do
  src="${REPO_DIR}/skills/${skill}"
  target="${DEST}/${skill}"
  rm -rf "$target"
  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$src" "$target"
    echo "Linked  ${skill} -> ${target}"
  else
    cp -R "$src" "$target"
    echo "Copied  ${skill} -> ${target}"
  fi
done

echo "Done. Installed ${#SKILLS[@]} skill(s) (${SCOPE}) into ${DEST}."

# Check Herdr CLI & built-in --skill dependencies
export_cli_skill() {
  local bin="$1"
  local skill_name="$2"
  local desc="$3"
  local out_dir="${DEST}/${skill_name}"
  local out_file="${out_dir}/SKILL.md"
  mkdir -p "$out_dir"
  {
    printf -- "---\nname: %s\ndescription: >-\n  %s\n---\n\n" "$skill_name" "$desc"
    "$bin" --skill
  } > "$out_file"
  echo "Exported ${bin} --skill -> ${out_file}"
}

check_cli_dep() {
  local bin="$1"
  local skill_name="$2"
  local desc="$3"
  local install_cmd="$4"

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo ""
    echo "[!] Missing dependency: '${bin}' is not installed."
    echo "    Install it first: ${install_cmd}"
    echo "    Then export its built-in skill with: ${bin} --skill"
    return
  fi

  if [[ ! -f "${DEST}/${skill_name}/SKILL.md" ]]; then
    if [[ "$WITH_DEPS" == "yes" ]]; then
      export_cli_skill "$bin" "$skill_name" "$desc"
    elif [[ "$WITH_DEPS" == "prompt" && -t 0 ]]; then
      echo ""
      read -r -p "[?] '${bin}' is installed, but '${DEST}/${skill_name}/SKILL.md' is missing. Export '${bin} --skill' there now? [y/N] " ans
      if [[ "$ans" =~ ^[Yy]$ ]]; then
        export_cli_skill "$bin" "$skill_name" "$desc"
      fi
    elif [[ "$WITH_DEPS" == "prompt" ]]; then
      echo "[i] Tip: '${DEST}/${skill_name}/SKILL.md' not found. Run with --with-deps (or '${bin} --skill') to install the ${bin} manual skill."
    fi
  fi
}

if [[ "$WITH_DEPS" != "no" ]]; then
  if [[ "$VARIANT" == "app" || "$VARIANT" == "all" ]]; then
    check_cli_dep "hc" "hc" \
      "Run, inspect, message, wait on, and orchestrate persistent terminals and coding agents with herdr-core (hc)." \
      "curl -fsSL https://releases.herdr.dev/core/install.sh | sh"
    check_cli_dep "herdr-app" "herdr-app" \
      "Drive and customize the Herdr desktop app window (herdr-app): spaces, tabs, panes, screenshots, and mods." \
      "curl -fsSL https://releases.herdr.dev/app/install.sh | sh"
  fi
  if [[ "$VARIANT" == "tui" || "$VARIANT" == "all" ]]; then
    check_cli_dep "herdr" "herdr" \
      "Operate and automate the Herdr TUI terminal multiplexer (herdr workspace, tab, pane, and agent commands)." \
      "curl -fsSL https://herdr.dev/install.sh | sh"
  fi
fi
