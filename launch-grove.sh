#!/usr/bin/env bash
# Launch zellij with per-worktree tabs (God Mode layout)
#
# This script delegates to launch-worktrees.sh which dynamically generates
# one tab per git worktree, each with LazyGit + AI Agent + Workbench panes.
#
# Usage:
#   ./launch-grove.sh                         # current dir, saved default agent
#   ./launch-grove.sh claude                  # current dir, claude
#   ./launch-grove.sh opencode                # current dir, opencode
#   ./launch-grove.sh codex                   # current dir, codex
#   ./launch-grove.sh /path/to/repo           # specific dir, opencode
#   ./launch-grove.sh claude /path/to/repo    # specific dir, claude
#   ./launch-grove.sh codex /path/to/repo     # specific dir, codex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ai-agent.sh
source "$SCRIPT_DIR/lib/ai-agent.sh"

usage() {
    cat <<'EOF'
Grove — AI-native terminal workspace

Daily workflow:
  grove                           Attach to or launch this repo's workspace
  grove new <branch>              Create a branch and worktree
  grove ls                        List worktrees
  grove pick                      Pick a worktree and change directory
  grove go <branch>               Jump to a worktree tab
  grove agent <branch> [ai]       Open or focus an AI agent tab
  grove status [path]             Show repository status

Session options:
  grove up --fresh [ai] [path]    Replace the existing repo session

Run `grove help --all` for advanced and compatibility commands.
EOF
}

full_usage() {
    cat <<'EOF'
Grove — git-style AI-native terminal workspace

Usage:
  grove <command> [args]
  grove [ai-editor] [path]      Shorthand for `grove up` (back-compat)

Workspace
  grove up [--fresh] [ai-editor] [path]
                                  Attach to or launch Zellij for this repo
  grove status [path]            Live worktree status dashboard
  grove agents                   Live dashboard of running AI agents

Worktrees
  grove new <branch>             Create a new branch + worktree
  grove add <branch>             Add a worktree for an existing branch
  grove ls                       List all worktrees
  grove rm <branch>              Remove a worktree (prompts to delete branch)
  grove cd <branch>              Jump into a worktree (shell cwd)
  grove pick                     Pick a worktree interactively, then cd into it
  grove main                     Jump into the main worktree (shell cwd)
  grove which <branch>           Print a worktree's path
  grove root                     Print the main worktree path
  grove run <branch> [--] <cmd>  Run a command inside a worktree's directory
  grove exec [--] <cmd>          Run a command in EVERY worktree (fan-out)
  grove sync [branch]            Fetch + rebase the branch onto its base
  grove pr [branch]              Open (or create) the branch's GitHub PR
  grove mv <branch> <new-path>   Move a worktree to a new directory
  grove log [branch]             git log of the branch vs base
  grove open <branch>            Open a worktree in your editor ($GROVE_EDITOR)
  grove info / diff / rename / prune / lock / unlock / tab

AI & navigation
  grove go <branch>              Jump to the worktree's Zellij tab (or attach)
  grove agent <branch> [ai]      Open/focus an AI agent tab for a worktree
  grove agents                   Live dashboard of running AI agents

Back-compat
  grove .                        Launch with the saved default agent
  grove claude [path]            Launch with Claude
  grove wt <cmd>                 Old worktree sub-dispatch (still works)
  wtab / wta / wtcd / wtls ...   Shell aliases (still work)

Environment Variables:
  GWT_BASE_BRANCH    Base branch for prune/diff/sync/log (default: origin/HEAD or main)
  GWT_WORKTREE_DIR   Override worktree parent directory
  GROVE_EDITOR       Editor for `grove open` (default: $EDITOR or code)
  AI_EDITOR          Override the saved default AI agent
EOF
}

print_command_names() {
    printf '%s\n' \
        up status agents \
        new add ls rm cd pick main which root \
        run exec sync pr mv log open info diff rename prune lock unlock tab \
        go agent help
}

if [[ "${1:-}" == "__commands" ]]; then
    print_command_names
    exit 0
fi

if [[ $# -eq 0 ]] && ! git rev-parse --show-toplevel &>/dev/null; then
    usage
    exit 0
fi

REPO_PATH=""
EXPLICIT_AI=""
FRESH_SESSION=false

is_ai_editor() {
    case "$1" in
        claude|gemini|opencode|codex|none) return 0 ;;
        *) return 1 ;;
    esac
}

# Worktree / AI verbs that are delegated to git-worktree.sh.
is_worktree_verb() {
    case "$1" in
        new|add|ls|list|rm|which|root|pick|run|exec|sync|pr|mv|log|open|go|agent|agents|status|info|diff|rename|prune|tab|lock|unlock|cd) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── git-style verb dispatch ────────────────────────────────────────────────
# Route `grove <verb>` to git-worktree.sh. `up` triggers the workspace launch.
# AI-editor names and paths fall through to the launch arg parser (back-compat).
case "${1:-}" in
    up)
        shift ;;                       # fall through to launch with remaining args
    wt|worktree)
        shift
        exec "$SCRIPT_DIR/git-worktree.sh" "$@" ;;
    help)
        if [[ "${2:-}" == "--all" ]]; then
            full_usage
        else
            usage
        fi
        exit 0 ;;
    *)
        if [[ -n "${1:-}" ]] && is_worktree_verb "$1"; then
            exec "$SCRIPT_DIR/git-worktree.sh" "$@"
        fi ;;
esac

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        --fresh)
            FRESH_SESSION=true
            shift
            ;;
        wt|worktree)
            shift
            exec "$SCRIPT_DIR/git-worktree.sh" "$@"
            ;;
        *)
            if is_ai_editor "$1"; then
                EXPLICIT_AI="$1"
            elif [[ -d "$1" ]]; then
                REPO_PATH="$(cd "$1" && pwd)"
            elif [[ -f "$1" ]]; then
                # File path given — use its parent directory (like VS Code)
                REPO_PATH="$(cd "$(dirname "$1")" && pwd)"
            else
                echo "Error: unrecognized argument '$1'"
                echo "Usage: grove [ai-editor] [path]"
                exit 1
            fi
            shift
            ;;
    esac
done

AI_EDITOR="$(grove_require_ai_choice "$EXPLICIT_AI")"

echo "Launching grove with AI_EDITOR=$AI_EDITOR (per-worktree tabs)"

if [[ -n "$REPO_PATH" ]]; then
    if $FRESH_SESSION; then
        exec "$SCRIPT_DIR/launch-worktrees.sh" --fresh --ai "$AI_EDITOR" "$REPO_PATH"
    fi
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR" "$REPO_PATH"
else
    if $FRESH_SESSION; then
        exec "$SCRIPT_DIR/launch-worktrees.sh" --fresh --ai "$AI_EDITOR"
    fi
    exec "$SCRIPT_DIR/launch-worktrees.sh" --ai "$AI_EDITOR"
fi
