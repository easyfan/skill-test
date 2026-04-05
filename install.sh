#!/usr/bin/env bash
# install.sh — skill-test plugin installer (entry point)
# Delegates to scripts/install.sh
# Usage: ./install.sh [--dry-run] [--uninstall] [--target=<path>]
#   --dry-run          Preview changes without writing
#   --uninstall        Remove installed files
#   --target=<path>    Custom Claude config directory (default: ~/.claude)
#   CLAUDE_DIR=<path>  Alternative to --target

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Forward --target=<path> to CLAUDE_DIR env var so scripts/install.sh picks it up
for arg in "$@"; do
  case "$arg" in
    --target=*) export CLAUDE_DIR="${arg#--target=}" ;;
  esac
done

exec bash "$SCRIPT_DIR/scripts/install.sh" "$@"
