#!/usr/bin/env bash
set -euo pipefail

VARIANT="all"
DEST="${HOME}/.agents/skills"
MODE="copy"

usage() {
  cat <<'EOF'
Install Herdr orchestration & worker skills for coding agents.

Usage:
  ./install.sh [options]

Options:
  --variant <app|tui|all>   Which Herdr CLI variant to install (default: all)
                              app -> herdr-orchestrator, herdr-worker (hc + herdr-app)
                              tui -> herdr-tui-orchestrator, herdr-tui-worker (herdr TUI)
                              all -> all four skills
  --dest <dir>              Destination skills directory (default: ~/.agents/skills)
  --antigravity, --agy      Install to Antigravity skills (~/.gemini/antigravity-cli/skills
                            if present, else ~/.gemini/config/skills)
  --agy-cli                 Shortcut for --dest ~/.gemini/antigravity-cli/skills
  --agy-ide                 Shortcut for --dest ~/.gemini/antigravity/skills
  --gemini                  Shortcut for --dest ~/.gemini/config/skills
  --claude                  Shortcut for --dest ~/.claude/skills
  --codex                   Shortcut for --dest ~/.codex/skills
  --pi                      Shortcut for --dest ~/.pi/agent/skills
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
    --dest)
      DEST="${2:-}"
      shift 2
      ;;
    --antigravity|--agy)
      if [[ -d "${HOME}/.gemini/antigravity-cli" ]]; then
        DEST="${HOME}/.gemini/antigravity-cli/skills"
      elif [[ -d "${HOME}/.gemini/antigravity" ]]; then
        DEST="${HOME}/.gemini/antigravity/skills"
      else
        DEST="${HOME}/.gemini/config/skills"
      fi
      shift
      ;;
    --agy-cli)
      DEST="${HOME}/.gemini/antigravity-cli/skills"
      shift
      ;;
    --agy-ide)
      DEST="${HOME}/.gemini/antigravity/skills"
      shift
      ;;
    --gemini)
      DEST="${HOME}/.gemini/config/skills"
      shift
      ;;
    --claude)
      DEST="${HOME}/.claude/skills"
      shift
      ;;
    --codex)
      DEST="${HOME}/.codex/skills"
      shift
      ;;
    --pi)
      DEST="${HOME}/.pi/agent/skills"
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

echo "Done. Installed ${#SKILLS[@]} skill(s) into ${DEST}."
