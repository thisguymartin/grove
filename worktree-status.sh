#!/usr/bin/env bash
# worktree-status.sh — Live dashboard for git worktree status
#
# Usage:
#   ./worktree-status.sh              # Use current directory
#   ./worktree-status.sh /path/repo   # Explicit repo path
#
# Designed to be run under `watch -n 2 -c` for live updates.
# Standalone: watch -n 2 -c ./worktree-status.sh

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"

# Resolve to git toplevel
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not a git repository: $REPO_PATH"
    exit 1
}

REPO_NAME=$(basename "$REPO_PATH")

# ---------------------------------------------------------------------------
# Colors (ANSI — works with watch -c)
# ---------------------------------------------------------------------------
BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo -e "${BOLD}Git Worktrees: ${CYAN}${REPO_NAME}${RESET}"
echo -e "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Parse worktrees and print status for each
# ---------------------------------------------------------------------------
wt_path=""
wt_branch=""
wt_head=""

print_worktree() {
    local path="$1" branch="$2" head="$3"

    # Derive display name
    local display_name
    if [[ -n "$branch" ]]; then
        display_name="${branch#refs/heads/}"
    else
        display_name="${head:0:7} (detached)"
    fi

    # Get changes
    local changes change_count
    changes=$(git -C "$path" status --short 2>/dev/null || echo "")
    if [[ -n "$changes" ]]; then
        change_count=$(echo "$changes" | wc -l | tr -d ' ')
    else
        change_count=0
    fi

    # Get ahead/behind remote
    local ahead_behind=""
    if [[ -n "$branch" ]]; then
        local branch_short="${branch#refs/heads/}"
        local upstream
        upstream=$(git -C "$path" rev-parse --abbrev-ref "${branch_short}@{upstream}" 2>/dev/null || echo "")
        if [[ -n "$upstream" ]]; then
            local ab
            ab=$(git -C "$path" rev-list --left-right --count "${branch_short}...${upstream}" 2>/dev/null || echo "")
            if [[ -n "$ab" ]]; then
                local ahead behind
                ahead=$(echo "$ab" | awk '{print $1}')
                behind=$(echo "$ab" | awk '{print $2}')
                if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
                    ahead_behind=" ${YELLOW}↑${ahead}↓${behind}${RESET}"
                elif [[ "$ahead" -gt 0 ]]; then
                    ahead_behind=" ${GREEN}↑${ahead}${RESET}"
                elif [[ "$behind" -gt 0 ]]; then
                    ahead_behind=" ${RED}↓${behind}${RESET}"
                fi
            fi
        fi
    fi

    # Get last commit
    local last_commit last_time
    last_commit=$(git -C "$path" log -1 --format="%h %s" 2>/dev/null || echo "unknown")
    last_time=$(git -C "$path" log -1 --format="%cr" 2>/dev/null || echo "")

    # Status indicator
    local status_icon
    if [[ "$change_count" -eq 0 ]]; then
        status_icon="${GREEN}clean${RESET}"
    else
        status_icon="${YELLOW}${change_count} changed${RESET}"
    fi

    # Print worktree info
    echo -e "${BOLD}${CYAN}[${display_name}]${RESET}  ${status_icon}${ahead_behind}"
    echo -e "  ${DIM}Path:${RESET} $path"
    echo -e "  ${DIM}Last:${RESET} $last_commit ${DIM}($last_time)${RESET}"

    # Show changed files if any
    if [[ -n "$changes" ]]; then
        echo -e "  ${DIM}Changes:${RESET}"
        echo "$changes" | head -10 | while IFS= read -r f; do
            local marker="${f:0:2}"
            local fname="${f:3}"
            case "$marker" in
                "M "|" M"|"MM") echo -e "    ${YELLOW}M${RESET} $fname" ;;
                "A "|"??"*)     echo -e "    ${GREEN}+${RESET} $fname" ;;
                "D "|" D")      echo -e "    ${RED}-${RESET} $fname" ;;
                "R "*)          echo -e "    ${CYAN}R${RESET} $fname" ;;
                *)              echo -e "    $f" ;;
            esac
        done
        if [[ "$change_count" -gt 10 ]]; then
            echo -e "    ${DIM}... and $((change_count - 10)) more${RESET}"
        fi
    fi

    echo ""
}

while IFS= read -r line; do
    case "$line" in
        worktree\ *)  wt_path="${line#worktree }" ;;
        branch\ *)    wt_branch="${line#branch }" ;;
        HEAD\ *)      wt_head="${line#HEAD }" ;;
        detached)     wt_branch="" ;;
        "")
            if [[ -n "$wt_path" ]]; then
                print_worktree "$wt_path" "$wt_branch" "$wt_head"
                wt_path="" wt_branch="" wt_head=""
            fi
            ;;
    esac
done < <(git -C "$REPO_PATH" worktree list --porcelain)

# Handle last entry if no trailing blank line
if [[ -n "$wt_path" ]]; then
    print_worktree "$wt_path" "$wt_branch" "$wt_head"
fi
