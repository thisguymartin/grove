#!/usr/bin/env bash
# ci-status.sh — Recent GitHub Actions runs for the current repo

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

echo -e "${BOLD}${CYAN}GitHub Actions${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

if ! command -v gh &>/dev/null; then
    echo -e "  ${DIM}gh CLI not installed${RESET}"
    echo -e "  ${DIM}Install: brew install gh${RESET}"
    exit 0
fi

if ! gh auth status &>/dev/null 2>&1; then
    echo -e "  ${DIM}gh not authenticated${RESET}"
    echo -e "  ${DIM}Run: gh auth login${RESET}"
    exit 0
fi

if ! git -C "$REPO_PATH" remote get-url origin &>/dev/null; then
    echo -e "  ${DIM}No origin remote found${RESET}"
    exit 0
fi

# Show recent workflow runs for this repository
if ! (cd "$REPO_PATH" && gh run list --limit 8); then
    echo -e "  ${YELLOW}Unable to load workflow runs${RESET}"
fi
