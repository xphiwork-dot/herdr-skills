#!/usr/bin/env bash
set -euo pipefail

VARIANT="all"
SCOPE="global"
PROJECT_DIR="$PWD"
AGENT="default"
CUSTOM_DEST=""
MODE="copy"

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
