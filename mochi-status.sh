#!/usr/bin/env bash
# mochi-status.sh — Live dashboard for Mochi task status
#
# Reads .mochi_manifest.json from the repo root and displays task status.
# Also reads PROGRESS.md from each worktree for latest iteration info.
#
# Usage:
#   ./mochi-status.sh              # Use current directory
#   ./mochi-status.sh /path/repo   # Explicit repo path

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"

# Resolve to git toplevel
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not a git repository: $REPO_PATH"
    exit 1
}

REPO_NAME=$(basename "$REPO_PATH")
MANIFEST="$REPO_PATH/.mochi_manifest.json"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'
DIM='\033[2m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo -e "${BOLD}Mochi Tasks: ${MAGENTA}${REPO_NAME}${RESET}"
echo -e "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Check for manifest
# ---------------------------------------------------------------------------
if [[ ! -f "$MANIFEST" ]]; then
    echo -e "${DIM}No Mochi tasks found (.mochi_manifest.json not present)${RESET}"
    exit 0
fi

# Require jq for JSON parsing
if ! command -v jq &>/dev/null; then
    echo -e "${RED}jq is required for mochi-status. Install: brew install jq${RESET}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse manifest and display each task
# ---------------------------------------------------------------------------
task_count=0
done_count=0
running_count=0
failed_count=0

for slug in $(jq -r 'keys[]' "$MANIFEST" 2>/dev/null); do
    task_count=$((task_count + 1))

    branch=$(jq -r --arg s "$slug" '.[$s].branch // "unknown"' "$MANIFEST")
    status=$(jq -r --arg s "$slug" '.[$s].status // "unknown"' "$MANIFEST")
    wt_path=$(jq -r --arg s "$slug" '.[$s].path // ""' "$MANIFEST")

    # Status styling
    case "$status" in
        done)
            status_display="${GREEN}done${RESET}"
            done_count=$((done_count + 1))
            ;;
        running)
            status_display="${YELLOW}running${RESET}"
            running_count=$((running_count + 1))
            ;;
        failed)
            status_display="${RED}failed${RESET}"
            failed_count=$((failed_count + 1))
            ;;
        pending)
            status_display="${DIM}pending${RESET}"
            ;;
        *)
            status_display="${DIM}${status}${RESET}"
            ;;
    esac

    echo -e "${BOLD}${MAGENTA}[${slug}]${RESET}  ${status_display}"
    echo -e "  ${DIM}Branch:${RESET} ${branch}"

    # Read PROGRESS.md from worktree if it exists
    if [[ -n "$wt_path" && -f "$wt_path/PROGRESS.md" ]]; then
        # Extract iteration and status lines from PROGRESS.md
        iteration=$(grep -oP '(?<=\*\*Iteration:\*\* )\d+' "$wt_path/PROGRESS.md" 2>/dev/null || echo "")
        progress_status=$(grep -oP '(?<=\*\*Status:\*\* ).+' "$wt_path/PROGRESS.md" 2>/dev/null || echo "")

        if [[ -n "$iteration" ]]; then
            echo -e "  ${DIM}Iteration:${RESET} ${iteration}"
        fi
        if [[ -n "$progress_status" ]]; then
            echo -e "  ${DIM}Progress:${RESET} ${progress_status}"
        fi
    fi

    # Read FEEDBACK.md if it exists (reviewer notes)
    if [[ -n "$wt_path" && -f "$wt_path/FEEDBACK.md" ]]; then
        feedback_line=$(head -5 "$wt_path/FEEDBACK.md" 2>/dev/null | grep -v '^#' | grep -v '^$' | head -1 || echo "")
        if [[ -n "$feedback_line" ]]; then
            # Truncate long feedback
            if [[ ${#feedback_line} -gt 80 ]]; then
                feedback_line="${feedback_line:0:77}..."
            fi
            echo -e "  ${DIM}Feedback:${RESET} ${feedback_line}"
        fi
    fi

    # Check if worktree path exists on disk
    if [[ -n "$wt_path" && ! -d "$wt_path" ]]; then
        echo -e "  ${RED}(worktree missing from disk)${RESET}"
    fi

    echo ""
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $task_count -eq 0 ]]; then
    echo -e "${DIM}Manifest is empty.${RESET}"
else
    parts=()
    [[ $done_count -gt 0 ]]    && parts+=("${GREEN}${done_count} done${RESET}")
    [[ $running_count -gt 0 ]] && parts+=("${YELLOW}${running_count} running${RESET}")
    [[ $failed_count -gt 0 ]]  && parts+=("${RED}${failed_count} failed${RESET}")
    pending_count=$((task_count - done_count - running_count - failed_count))
    [[ $pending_count -gt 0 ]] && parts+=("${DIM}${pending_count} pending${RESET}")

    summary=$(IFS=", "; echo "${parts[*]}")
    echo -e "${DIM}Total: ${task_count} task(s) — ${RESET}${summary}"
fi
