#!/usr/bin/env bash
# Launch zellij with per-worktree tabs (God Mode layout)
#
# This script delegates to launch-worktrees.sh which dynamically generates
# one tab per git worktree, each with LazyGit + AI Agent + Workbench panes.
#
# Usage:
#   ./launch-grove.sh                         # current dir, claude
#   ./launch-grove.sh opencode                # current dir, opencode
#   ./launch-grove.sh /path/to/repo           # specific dir, claude
#   ./launch-grove.sh /path/to/repo gemini    # specific dir, gemini

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_PATH=""
AI_EDITOR=""

# Parse args: if an arg is a directory -> repo path, otherwise -> AI editor
for arg in "$@"; do
    if [[ -d "$arg" ]]; then
        REPO_PATH="$arg"
    else
        AI_EDITOR="$arg"
    fi
done

AI_EDITOR="${AI_EDITOR:-claude}"

echo "Launching grove with AI_EDITOR=$AI_EDITOR (per-worktree tabs)"

if [[ -n "$REPO_PATH" ]]; then
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR" "$REPO_PATH"
else
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR"
fi
