#!/usr/bin/env bash
# stash-status.sh — Global stash and WIP tracker across worktrees

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not a git repository: $REPO_PATH"
    exit 1
}

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}Global Stash & WIP${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

echo -e "${BOLD}Stashes${RESET}"
stash_output=$(git -C "$REPO_PATH" stash list 2>/dev/null || true)
if [[ -z "$stash_output" ]]; then
    echo -e "  ${DIM}No stashes${RESET}"
else
    count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        count=$((count + 1))
        if [[ $count -le 8 ]]; then
            echo -e "  ${YELLOW}${line}${RESET}"
        fi
    done <<< "$stash_output"

    if [[ $count -gt 8 ]]; then
        echo -e "  ${DIM}... and $((count - 8)) more${RESET}"
    fi
fi

echo ""
echo -e "${BOLD}Dirty Worktrees${RESET}"

dirty_found=false
wt_path=""
wt_branch=""
wt_head=""

print_worktree_wip() {
    local path="$1"
    local branch="$2"
    local head="$3"

    local display_name
    if [[ -n "$branch" ]]; then
        display_name="${branch#refs/heads/}"
    else
        display_name="${head:0:7} (detached)"
    fi

    local changes
    changes=$(git -C "$path" status --porcelain 2>/dev/null || true)
    if [[ -z "$changes" ]]; then
        return
    fi

    dirty_found=true
    local change_count
    change_count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')

    echo -e "  ${RED}✗${RESET} ${BOLD}${display_name}${RESET}  ${YELLOW}${change_count} changed${RESET}"

    local shown=0
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        shown=$((shown + 1))
        if [[ $shown -gt 4 ]]; then
            break
        fi
        echo -e "      ${DIM}${row}${RESET}"
    done <<< "$changes"

    if [[ $change_count -gt 4 ]]; then
        echo -e "      ${DIM}... and $((change_count - 4)) more${RESET}"
    fi
}

while IFS= read -r line; do
    case "$line" in
        worktree\ *) wt_path="${line#worktree }" ;;
        branch\ *)   wt_branch="${line#branch }" ;;
        HEAD\ *)     wt_head="${line#HEAD }" ;;
        detached)     wt_branch="" ;;
        "")
            if [[ -n "$wt_path" ]]; then
                print_worktree_wip "$wt_path" "$wt_branch" "$wt_head"
                wt_path=""; wt_branch=""; wt_head=""
            fi
            ;;
    esac
done < <(git -C "$REPO_PATH" worktree list --porcelain)

if [[ -n "$wt_path" ]]; then
    print_worktree_wip "$wt_path" "$wt_branch" "$wt_head"
fi

if ! $dirty_found; then
    echo -e "  ${GREEN}✓ All worktrees clean${RESET}"
fi
