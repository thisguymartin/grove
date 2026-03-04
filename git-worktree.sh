#!/usr/bin/env bash
# Git Worktree Management Toolkit
#
# A set of commands for managing git worktrees with a consistent directory
# structure. Worktrees are created under a sibling "worktrees/" directory
# next to your main repo clone.
#
# Usage:
#   git-worktree.sh add <branch>            # Add worktree for an existing remote branch
#   git-worktree.sh new <branch>            # Create a new branch and worktree
#   git-worktree.sh rm  <branch>            # Remove a worktree (and optionally its branch)
#   git-worktree.sh ls                      # List all worktrees
#   git-worktree.sh prune                   # Remove worktrees whose branches are merged/gone
#   git-worktree.sh tab                     # Launch Zellij with a tab per worktree
#   git-worktree.sh tab --layout-only       # Print the generated Zellij layout to stdout
#
# Environment:
#   GWT_BASE_BRANCH  - Base branch for prune comparison (default: main)
#   GWT_WORKTREE_DIR - Override the worktree parent directory

set -euo pipefail

# ─── Helpers ──────────────────────────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Error: not inside a git repository."
    exit 1
}

REPO_NAME="$(basename "$REPO_ROOT")"
PARENT_DIR="$(dirname "$REPO_ROOT")"
WORKTREE_DIR="${GWT_WORKTREE_DIR:-${PARENT_DIR}/worktrees/${REPO_NAME}}"
BASE_BRANCH="${GWT_BASE_BRANCH:-main}"

ensure_worktree_dir() {
    if [[ ! -d "$WORKTREE_DIR" ]]; then
        mkdir -p "$WORKTREE_DIR"
    fi
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_add() {
    local branch="${1:?Usage: git-worktree.sh add <branch>}"
    local target="${WORKTREE_DIR}/${branch}"

    ensure_worktree_dir

    if [[ -d "$target" ]]; then
        echo "Worktree already exists at $target"
        exit 0
    fi

    # Fetch the branch from origin if it exists remotely
    git fetch origin "$branch" 2>/dev/null || true
    git worktree add "$target" "$branch"
    echo "Worktree added: $target (branch: $branch)"
}

cmd_new() {
    local branch="${1:?Usage: git-worktree.sh new <branch>}"
    local target="${WORKTREE_DIR}/${branch}"

    ensure_worktree_dir

    if [[ -d "$target" ]]; then
        echo "Worktree already exists at $target"
        exit 0
    fi

    git worktree add "$target" -b "$branch"
    echo "Worktree created: $target (new branch: $branch)"
}

cmd_rm() {
    local branch="${1:?Usage: git-worktree.sh rm <branch>}"
    local target="${WORKTREE_DIR}/${branch}"

    if [[ ! -d "$target" ]]; then
        echo "No worktree found at $target"
        exit 1
    fi

    git worktree remove --force "$target"
    echo "Worktree removed: $target"

    # Offer to delete the branch
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        read -rp "Delete local branch '$branch'? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            git branch -D "$branch"
            echo "Branch '$branch' deleted."
        fi
    fi
}

cmd_ls() {
    echo "Git Worktrees for ${REPO_NAME}:"
    echo "─────────────────────────────────────────"
    git worktree list --porcelain | awk '
        $1 == "worktree" { wt = $2 }
        $1 == "branch"   { br = $2; sub(/^refs\/heads\//, "", br) }
        $1 == "HEAD"     { head = $2 }
        $1 == "detached" { br = "(detached)" }
        $1 == "locked"   { locked = " [locked]" }
        /^$/ {
            if (wt != "") {
                printf "  %-50s %s%s\n", wt, br, locked
            }
            wt = br = head = locked = ""
        }
        END {
            if (wt != "") {
                printf "  %-50s %s%s\n", wt, br, locked
            }
        }
    '
}

cmd_prune() {
    echo "Pruning merged/stale worktrees (base: $BASE_BRANCH)..."

    # First, let git clean up any broken worktree references
    git worktree prune

    # Fetch to get latest remote state
    git fetch -p origin 2>/dev/null || true

    local pruned=0

    git worktree list --porcelain | awk '
        $1 == "worktree" { wt = $2 }
        $1 == "branch"   { br = $2; sub(/^refs\/heads\//, "", br) }
        $1 == "locked"   { locked = 1 }
        /^$/ {
            if (wt != "" && locked != 1) {
                print wt "\t" br
            }
            wt = br = ""; locked = 0
        }
        END {
            if (wt != "" && locked != 1) {
                print wt "\t" br
            }
        }
    ' | while IFS=$'\t' read -r wt br; do
        # Skip the main worktree
        if [[ "$wt" == "$REPO_ROOT" ]]; then
            continue
        fi

        # Skip if branch matches the base branch
        if [[ "$br" == "$BASE_BRANCH" ]]; then
            continue
        fi

        # Check if the branch has been merged into the base branch
        if git merge-base --is-ancestor "refs/heads/$br" "refs/heads/$BASE_BRANCH" 2>/dev/null; then
            echo "  Removing (merged): $wt [$br]"
            git worktree remove --force "$wt"
            pruned=$((pruned + 1))
            continue
        fi

        # Check if the remote tracking branch is gone
        if ! git show-ref --verify --quiet "refs/remotes/origin/$br" 2>/dev/null; then
            # Branch has no remote tracking — check if it's been squash-merged
            # by comparing patch IDs
            local branch_patch
            branch_patch=$(git diff "$BASE_BRANCH...$br" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}' | head -n1) || true

            if [[ -z "$branch_patch" ]]; then
                continue
            fi

            local found=""
            while IFS= read -r commit; do
                local commit_patch
                commit_patch=$(git diff "$commit^..$commit" 2>/dev/null | git patch-id --stable 2>/dev/null | awk '{print $1}' | head -n1) || true
                if [[ "$commit_patch" == "$branch_patch" ]]; then
                    found="$commit"
                    break
                fi
            done < <(git log --format="%H" "$BASE_BRANCH" --since="4 weeks ago" 2>/dev/null)

            if [[ -n "$found" ]]; then
                echo "  Removing (squash-merged): $wt [$br]"
                git worktree remove --force "$wt"
                pruned=$((pruned + 1))
            fi
        fi
    done

    if [[ "$pruned" -eq 0 ]]; then
        echo "  Nothing to prune."
    else
        echo "  Pruned $pruned worktree(s)."
    fi
}

cmd_tab() {
    local layout_only=false
    if [[ "${1:-}" == "--layout-only" ]]; then
        layout_only=true
    fi

    # Collect worktree information
    local -a wt_paths=()
    local -a wt_branches=()

    while IFS=$'\t' read -r wt br; do
        wt_paths+=("$wt")
        wt_branches+=("$br")
    done < <(
        git worktree list --porcelain | awk '
            $1 == "worktree" { wt = $2 }
            $1 == "branch"   { br = $2; sub(/^refs\/heads\//, "", br) }
            $1 == "detached" { br = "(detached)" }
            /^$/ {
                if (wt != "") print wt "\t" br
                wt = br = ""
            }
            END {
                if (wt != "") print wt "\t" br
            }
        '
    )

    if [[ ${#wt_paths[@]} -eq 0 ]]; then
        echo "No worktrees found."
        exit 1
    fi

    # Generate a KDL layout with one tab per worktree
    local layout
    layout=$(generate_tab_layout "${wt_paths[@]}" -- "${wt_branches[@]}")

    if $layout_only; then
        echo "$layout"
        exit 0
    fi

    local layout_file
    layout_file=$(mktemp /tmp/gwt-tabs-XXXXXXXX)
    trap 'rm -f "'"$layout_file"'"' EXIT
    echo "$layout" > "$layout_file"

    local session_name="worktrees-${REPO_NAME}"

    echo "Launching Zellij with ${#wt_paths[@]} worktree tab(s)..."
    for i in "${!wt_paths[@]}"; do
        echo "  [Tab $((i+1))] ${wt_branches[$i]} -> ${wt_paths[$i]}"
    done
    echo ""
    echo "Session: $session_name"
    echo "Tip: Use Alt+Left/Right to switch between worktree tabs"
    echo ""

    ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_NAME:-}"
    if [[ -n "$ZELLIJ_SESSION_NAME" ]] || [[ "${ZELLIJ:-}" == "0" ]]; then
        echo ""
        echo "Error: already inside Zellij session '${ZELLIJ_SESSION_NAME:-unknown}'."
        echo "Detach first (Ctrl+o, d), then re-run this command."
        rm -f "$layout_file"
        exit 1
    fi

    # Kill existing session with the same name if it exists
    if zellij list-sessions 2>/dev/null | grep -qw "$session_name"; then
        echo "Killing existing Zellij session: $session_name"
        zellij kill-session "$session_name" 2>/dev/null || true
        sleep 0.5
    fi

    zellij --new-session-with-layout "$layout_file" --session "$session_name"
}

generate_tab_layout() {
    # Parse args: paths... -- branches...
    local -a paths=()
    local -a branches=()
    local parsing_branches=false

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            parsing_branches=true
            continue
        fi
        if $parsing_branches; then
            branches+=("$arg")
        else
            paths+=("$arg")
        fi
    done

    # Start layout
    cat <<'HEADER'
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"
        }
    }
HEADER

    # AI editor (default: claude, override with AI_EDITOR env var)
    local ai_editor="${AI_EDITOR:-claude}"

    # Tab color palette — cycles through these for each worktree tab
    local -a tab_colors=("green" "blue" "yellow" "magenta" "cyan" "orange" "red")

    # One tab per worktree
    for i in "${!paths[@]}"; do
        local path="${paths[$i]}"
        local branch="${branches[$i]}"
        local color_index=$((i % ${#tab_colors[@]}))
        local tab_color="${tab_colors[$color_index]}"

        cat <<EOF

    tab name="${branch}" color="${tab_color}" {
        // TOP: LazyGit + AI Agent side by side
        pane split_direction="vertical" size="70%" {
            pane command="lazygit" name="LazyGit" {
                cwd "${path}"
            }
            pane command="${ai_editor}" name="AI Agent" {
                cwd "${path}"
                focus true
            }
        }
        // BOTTOM: Workbench shell
        pane name="Workbench" {
            cwd "${path}"
        }
    }
EOF
    done

    # Overview tab: live dashboard of all worktrees
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    cat <<FOOTER

    tab name="Overview" color="cyan" {
        pane split_direction="vertical" {
            pane command="watch" name="Worktree Status" size="60%" {
                args "-n" "2" "-c" "${script_dir}/worktree-status.sh" "${REPO_ROOT}"
            }
            pane name="worktree-mgmt" size="40%" {
                cwd "${REPO_ROOT}"
            }
        }
    }
}
FOOTER
}

# ─── Main Dispatch ────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
Git Worktree Management Toolkit

Usage:
  git-worktree.sh <command> [args]

Commands:
  add   <branch>     Add a worktree for an existing branch
  new   <branch>     Create a new branch + worktree
  rm    <branch>     Remove a worktree (prompts to delete branch)
  ls                 List all worktrees
  prune              Remove worktrees for merged/stale branches
  tab                Launch Zellij with one tab per worktree
  tab --layout-only  Print the generated Zellij layout (no launch)
  help               Show this help message

Environment Variables:
  GWT_BASE_BRANCH    Base branch for prune (default: main)
  GWT_WORKTREE_DIR   Override worktree parent directory

Examples:
  git-worktree.sh new feature/login        # Create worktree + branch
  git-worktree.sh add bugfix/header        # Add worktree for existing branch
  git-worktree.sh ls                       # List all worktrees
  git-worktree.sh tab                      # Open each worktree in its own tab
  git-worktree.sh rm feature/login         # Remove worktree
  git-worktree.sh prune                    # Clean up merged worktrees

Shell Aliases (add to ~/.zshrc or ~/.bashrc):
  alias gwt='~/workspace/grove/git-worktree.sh'
  alias gwta='gwt add'
  alias gwtn='gwt new'
  alias gwtrm='gwt rm'
  alias gwtls='gwt ls'
  alias gwtp='gwt prune'
  alias gwtt='gwt tab'
EOF
}

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    add)    cmd_add "$@" ;;
    new)    cmd_new "$@" ;;
    rm)     cmd_rm "$@" ;;
    ls)     cmd_ls ;;
    list)   cmd_ls ;;
    prune)  cmd_prune ;;
    tab)    cmd_tab "$@" ;;
    help|--help|-h) usage ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run 'git-worktree.sh help' for usage."
        exit 1
        ;;
esac
