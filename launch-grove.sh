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

usage() {
    cat <<'EOF'
Grove — AI-native terminal workspace

Usage:
  grove [options] [path] [ai-editor]

Arguments:
  path        Path to a git repo (default: current directory)
  ai-editor   AI agent to use: claude | gemini | opencode (default: claude)

Options:
  -h, --help  Show this help message

Examples:
  grove                          Launch with Claude in current repo
  grove gemini                   Launch with Gemini in current repo
  grove /path/to/repo            Launch with Claude in specified repo
  grove /path/to/repo opencode   Launch with OpenCode in specified repo

Worktree Commands (run from inside a git repo):
  grove wt add <branch>          Add worktree for an existing branch
  grove wt new <branch>          Create a new branch + worktree
  grove wt rm  <branch>          Remove a worktree (delete a branch)
  grove wt ls                    List all worktrees
  grove wt prune                 Remove worktrees for merged/stale branches
  grove wt info [branch]         Show path, HEAD, ahead/behind, dirty status
  grove wt diff [branch]         Show diff vs base branch
  grove wt rename <old> <new>    Rename a worktree's branch
  grove wt lock <path>           Lock a worktree
  grove wt unlock <path>         Unlock a worktree
  grove wt cd <branch>           Print the path of a worktree by branch name

Shell Aliases (from git-worktree-aliases.sh):
  wtab <branch>   Create new branch + worktree
  wta  <branch>   Add worktree for existing branch
  wtrm <path>     Force remove worktree
  wtls            List worktrees
  wtp             Prune merged worktrees
  wtcd <branch>   cd into a worktree

Environment Variables:
  GWT_BASE_BRANCH    Base branch for prune/diff (default: main)
  GWT_WORKTREE_DIR   Override worktree parent directory
  AI_EDITOR          Default AI editor (default: claude)
EOF
}

REPO_PATH=""
AI_EDITOR=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        wt|worktree)
            shift
            exec "$SCRIPT_DIR/git-worktree.sh" "$@"
            ;;
        *)
            if [[ -d "$1" ]]; then
                REPO_PATH="$1"
            else
                AI_EDITOR="$1"
            fi
            shift
            ;;
    esac
done

AI_EDITOR="${AI_EDITOR:-claude}"

echo "Launching grove with AI_EDITOR=$AI_EDITOR (per-worktree tabs)"

if [[ -n "$REPO_PATH" ]]; then
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR" "$REPO_PATH"
else
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR"
fi
