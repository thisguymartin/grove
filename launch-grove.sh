#!/usr/bin/env bash
# Launch zellij with per-worktree tabs (God Mode layout)
#
# This script delegates to launch-worktrees.sh which dynamically generates
# one tab per git worktree, each with LazyGit + AI Agent + Workbench panes.
#
# Usage:
#   ./launch-grove.sh              # Uses claude (default)
#   ./launch-grove.sh opencode     # Uses opencode
#   ./launch-grove.sh claude       # Uses claude explicitly

set -euo pipefail

# Set the AI editor (default to claude)
AI_EDITOR="${1:-claude}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🌳 Launching grove with AI_EDITOR=$AI_EDITOR (per-worktree tabs)"

exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR"
