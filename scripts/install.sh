#!/usr/bin/env bash
# scripts/install.sh — skill-test plugin installer (core logic)
# Usage: ./install.sh [--dry-run] [--uninstall] [--target=<path>]
# Options:
#   --dry-run          Preview changes without writing
#   --uninstall        Remove installed files
#   --target=<path>    Custom Claude config directory (default: ~/.claude)
#   CLAUDE_DIR=<path>  Alternative to --target

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DRY_RUN=false
UNINSTALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --uninstall)  UNINSTALL=true ;;
    --target=*)   CLAUDE_DIR="${arg#--target=}" ;;
  esac
done

SKILL_SRC="skills/skill-test"
SKILL_DST="skills/skill-test"
CMD_SRC="commands/skill-test.md"
CMD_DST="commands/skill-test.md"

# ── Uninstall ──────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
  echo "Uninstalling skill-test..."
  skill_dst="$CLAUDE_DIR/$SKILL_DST"
  if [ -d "$skill_dst" ]; then
    if $DRY_RUN; then
      echo "[dry-run] rm -rf $skill_dst"
    else
      rm -rf "$skill_dst"
    fi
    echo "  Removed $skill_dst"
  fi
  cmd_dst="$CLAUDE_DIR/$CMD_DST"
  if [ -f "$cmd_dst" ]; then
    if $DRY_RUN; then
      echo "[dry-run] rm $cmd_dst"
    else
      rm "$cmd_dst"
    fi
    echo "  Removed $cmd_dst"
  fi
  echo "Uninstall complete."
  exit 0
fi

# ── Install ────────────────────────────────────────────────────────────────────
echo "Installing skill-test..."

MODIFIED=0

# Install skill (SKILL.md + references/)
skill_src="$PLUGIN_DIR/$SKILL_SRC"
skill_dst="$CLAUDE_DIR/$SKILL_DST"

need_copy=false
if [ ! -f "$skill_dst/SKILL.md" ]; then
  need_copy=true
elif ! diff -q "$skill_src/SKILL.md" "$skill_dst/SKILL.md" &>/dev/null; then
  need_copy=true
fi

if $need_copy; then
  if $DRY_RUN; then
    echo "[dry-run] cp -r $skill_src/ $skill_dst/"
  else
    mkdir -p "$skill_dst"
    cp -r "$skill_src/." "$skill_dst/"
  fi
  MODIFIED=$((MODIFIED + 1))
fi

# Install command entry point (commands/skill-test.md)
cmd_src="$PLUGIN_DIR/$CMD_SRC"
cmd_dst="$CLAUDE_DIR/$CMD_DST"

need_cmd=false
if [ ! -f "$cmd_dst" ]; then
  need_cmd=true
elif ! diff -q "$cmd_src" "$cmd_dst" &>/dev/null; then
  need_cmd=true
fi

if $need_cmd; then
  if $DRY_RUN; then
    echo "[dry-run] cp $cmd_src $cmd_dst"
  else
    mkdir -p "$(dirname "$cmd_dst")"
    cp "$cmd_src" "$cmd_dst"
  fi
  MODIFIED=$((MODIFIED + 1))
fi

if $DRY_RUN; then
  echo "${MODIFIED} files would be modified"
fi
echo ""
echo "Done! ${MODIFIED} items installed."
echo ""
echo "Usage: /skill-test [--from-stage N] <target>"
echo "       /skill-test [--from-stage N] --pattern <name>"
