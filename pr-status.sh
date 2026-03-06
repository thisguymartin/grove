#!/usr/bin/env bash
# pr-status.sh — Live PR/CI status dashboard for Grove worktree branches
#
# Shows open PRs for each worktree branch with CI and review status.
# Requires: gh (GitHub CLI), authenticated
#
# Designed to run in a loop: while true; do clear; ./pr-status.sh /path/repo; sleep 60; done

set -euo pipefail

REPO_PATH="${1:-$(pwd)}"
REPO_PATH=$(git -C "$REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not a git repository: $REPO_PATH"
    exit 1
}

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
RED='\033[31m'
DIM='\033[2m'
MAGENTA='\033[35m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}PR & CI Status${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

# Check gh CLI
if ! command -v gh &>/dev/null; then
    echo -e "  ${DIM}gh CLI not installed${RESET}"
    echo -e "  ${DIM}Install: brew install gh${RESET}"
    exit 0
fi

# Check authentication
if ! gh auth status &>/dev/null 2>&1; then
    echo -e "  ${DIM}gh not authenticated${RESET}"
    echo -e "  ${DIM}Run: gh auth login${RESET}"
    exit 0
fi

# Get worktree branches
branches=()
while IFS= read -r line; do
    case "$line" in
        branch\ *) branches+=("${line#branch refs/heads/}") ;;
    esac
done < <(git -C "$REPO_PATH" worktree list --porcelain)

if [[ ${#branches[@]} -eq 0 ]]; then
    echo -e "  ${DIM}No worktree branches found${RESET}"
    exit 0
fi

# Query PRs for the repo
pr_json=$(cd "$REPO_PATH" && gh pr list \
    --json number,title,headRefName,state,statusCheckRollup,reviewDecision,additions,deletions,isDraft \
    --limit 50 2>/dev/null || echo "[]")

# Use Python to match branches to PRs and format output
python3 - "$pr_json" "${branches[@]}" <<'PYEOF'
import sys, json

pr_data = json.loads(sys.argv[1])
branches = sys.argv[2:]

BOLD = '\033[1m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RED = '\033[31m'
CYAN = '\033[36m'
DIM = '\033[2m'
MAGENTA = '\033[35m'
RESET = '\033[0m'

# Index PRs by branch
pr_by_branch = {}
for pr in pr_data:
    pr_by_branch[pr['headRefName']] = pr

has_prs = False

for branch in branches:
    pr = pr_by_branch.get(branch)
    if pr:
        has_prs = True
        num = pr['number']
        title = pr['title']
        if len(title) > 45:
            title = title[:42] + "..."

        # Draft status
        draft_str = f" {DIM}(draft){RESET}" if pr.get('isDraft') else ""

        # CI status
        checks = pr.get('statusCheckRollup', []) or []
        if not checks:
            ci = f"{DIM}no checks{RESET}"
        else:
            states = [c.get('conclusion') or c.get('status', '') for c in checks]
            if all(s == 'SUCCESS' for s in states):
                ci = f"{GREEN}passed{RESET}"
            elif any(s == 'FAILURE' for s in states):
                failed = sum(1 for s in states if s == 'FAILURE')
                ci = f"{RED}failed ({failed}){RESET}"
            elif any(s in ('PENDING', 'IN_PROGRESS', 'QUEUED') for s in states):
                ci = f"{YELLOW}running{RESET}"
            else:
                ci = f"{DIM}unknown{RESET}"

        # Review status
        review = pr.get('reviewDecision', '')
        if review == 'APPROVED':
            rev = f"{GREEN}approved{RESET}"
        elif review == 'CHANGES_REQUESTED':
            rev = f"{RED}changes requested{RESET}"
        elif review == 'REVIEW_REQUIRED':
            rev = f"{YELLOW}review needed{RESET}"
        else:
            rev = f"{DIM}no review{RESET}"

        # Diff stats
        adds = pr.get('additions', 0)
        dels = pr.get('deletions', 0)
        diff_str = f"{GREEN}+{adds}{RESET}/{RED}-{dels}{RESET}"

        print(f"  {CYAN}#{num}{RESET} {title}{draft_str}")
        print(f"    {DIM}{branch}{RESET}  CI: {ci}  {rev}  {diff_str}")
    else:
        print(f"  {DIM}- {branch} — no PR{RESET}")

if not has_prs and branches:
    print(f"\n  {DIM}No open PRs for any worktree branch{RESET}")
PYEOF
